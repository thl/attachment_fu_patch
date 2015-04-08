# AttachmentFuPatch
require 'fileutils'
module Technoweenie # :nodoc:
  module AttachmentFu # :nodoc:    
    module ClassMethods
      @@content_types = Image::VALID_MIME_TYPES
      @@supported_raw_formats = ['cr2', 'crw', 'nef', 'dng', 'raf']

      mattr_reader :content_types, :supported_raw_formats
      
      def convert_if_necessary(file, filename, rotation)
        ext = File.extname(filename) # on purpose not using file since tempfile may loose extension.
        ext = ext[1...ext.size].downcase if !ext.blank?
        if supported_raw_formats.include? ext
          begin
            # Log the failure to load the image.  This should match ::Magick::ImageMagickError
            # but that would cause acts_as_attachment to require rmagick.
            if rotation.nil?
              message = `ufraw-batch '#{file}' --overwrite '--out-path=#{Technoweenie::AttachmentFu.tempfile_path}'` # add --rotate=angle
            else
              message = `ufraw-batch '#{file}' --overwrite '--out-path=#{Technoweenie::AttachmentFu.tempfile_path}' --rotate=#{rotation}` # add --rotate=angle
            end
            base_name = "#{File.basename(file,'.*')}.ppm"
            original_temp = File.expand_path(File.join(Technoweenie::AttachmentFu.tempfile_path, base_name))
            raise "Format for #{self.filename} could not be processed: #{message}" unless File.exists?(original_temp)
            new_temp = copy_to_temp_file(original_temp, "#{rand Time.now.to_i}_#{base_name}")
            FileUtils::rm original_temp
            return new_temp
          rescue
            logger.debug("Exception working with image: #{$!}")
            return file
          end
        else
          if rotation.nil?
            return file
          else
            original_temp = File.expand_path(File.join(Technoweenie::AttachmentFu.tempfile_path, filename))
            Magick::Image.read(file).first.rotate(rotation).write(original_temp)
            raise "Could not rotate #{filename}: #{message}" unless File.exists?(original_temp)
            new_temp = copy_to_temp_file(original_temp, "#{rand Time.now.to_i}_#{filename}")
            FileUtils::rm original_temp
            return new_temp
          end
        end
      end
    end
    
    module InstanceMethods
      # This method handles the uploaded file object.  If you set the field name to uploaded_data, you don't need
      # any special code in your controller.
      #
      #   <% form_for :attachment, :html => { :multipart => true } do |f| -%>
      #     <p><%= f.file_field :uploaded_data %></p>
      #     <p><%= submit_tag :Save %>
      #   <% end -%>
      #
      #   @attachment = Attachment.create! params[:attachment]
      #
      # TODO: Allow it to work with Merb tempfiles too.
      alias_method :__uploaded_data=, :uploaded_data=
      
      def uploaded_data=(file_data)
        self.__uploaded_data=file_data
        if self.content_type=='application/octet-stream'
          self.content_type = Image::VALID_TYPES[FilenameUtils.extension_without_dot(self.filename).downcase]
        end
      end
      
      def temp_path=(file_data)
        self.temp_paths.unshift file_data
      end
      
      # Gets the thumbnail name for a filename.  'foo.jpg' becomes 'foo_thumbnail.jpg'
      def thumbnail_name_for(thumbnail = nil)
        return filename if thumbnail.blank?
        "#{FilenameUtils.basename(filename)}_#{thumbnail}.jpg"
      end
      
      def convert_if_necessary(file, rotation=nil)
        self.class.convert_if_necessary(file, self.filename, rotation)
      end
      
      def create_or_update_thumbnail(temp_file, file_name_suffix, size)
        thumbnailable? || raise(ThumbnailError.new("Can't create a thumbnail if the content type is not an image or there is no parent_id column"))
        find_or_initialize_thumbnail(file_name_suffix).tap do |thumb|
          thumb.temp_paths.unshift temp_file
          thumb.send(:assign_attributes, {
            :content_type             => content_type,
            :filename                 => thumbnail_name_for(file_name_suffix),
            :thumbnail_resize_options => size
          })
          callback_with_args :before_thumbnail_saved, thumb
          thumb.save!
        end
      end
      
      def update_thumbnails(rotation = nil)
        if respond_to?(:process_attachment_with_processing, true) && thumbnailable? && !attachment_options[:thumbnails].blank? && parent_id.nil?
          temp_file = convert_if_necessary(temp_path || create_temp_file, rotation)
          attachment_options[:thumbnails].each { |suffix, size|
            if size.is_a?(Symbol)
              parent_type = polymorphic_parent_type
              next unless parent_type && [parent_type, parent_type.tableize].include?(suffix.to_s) && respond_to?(size)
              size = send(size)
            #end
            #if size.is_a?(Hash)
            #  parent_type = polymorphic_parent_type
            #  next unless parent_type && [parent_type, parent_type.tableize].include?(suffix.to_s)
            #  size.each { |ppt_suffix, ppt_size|
            #    create_or_update_thumbnail(temp_file, ppt_suffix, *ppt_size)
            #  }
            else
              create_or_update_thumbnail(temp_file, suffix, size)
            end
          }
        end
        @temp_paths.clear
        @saved_attachment = nil
      end
      
      # Cleans up after processing.  Thumbnails are created, the attachment is stored to the backend, and the temp_paths are cleared.
      def after_process_attachment
        if @saved_attachment
          save_to_storage
          update_thumbnails
          callback_with_args :after_attachment_saved, nil
        end
      end
      
      def date_time_original
        date_time_str = properties['exif:DateTimeOriginal']
        date_time_str = properties['tiff:timestamp'] if date_time_str.nil?
        if !date_time_str.blank?
          date = nil
          begin
            date = DateTime.parse(date_time_str.split(":",3).join("-"))
          rescue Exception => exc
            return date_time_str
          end
          return date
        end
        return nil
      end
      
      def make
        make_str = properties['exif:Make']
        make_str = properties['tiff:make'] if make_str.nil?
        return make_str
      end
      
      def model
        model_str = properties['exif:Model']
        model_str = properties['tiff:model'] if model_str.nil?
        return model_str
      end
      
      private
      
      def properties
        @properties ||= nil
        if @properties.nil?
          with_image{|img| @properties = self.class.properties(img)  }
          @properties = {} if @properties.nil?
        end
        return @properties
      end
    end
    
    module Processors
      module RmagickProcessor        
        module ClassMethods
          def properties(img)
            img.get_exif_by_entry
            return img.properties
          end
        end
        
        protected
        
        # Performs the actual resizing operation for a thumbnail
        def resize_image(img, size_options)
          if size_options.is_a?(Hash)
            size =  size_options[:geometry]
            density = size_options[:density]
            quality = size_options[:quality]
          else 
            size = size_options
          end
          size = size.first if size.is_a?(Array) && size.length == 1 && !size.first.is_a?(Fixnum)
          if size.is_a?(Fixnum) || (size.is_a?(Array) && size.first.is_a?(Fixnum))
            size = [size, size] if size.is_a?(Fixnum)
            img.thumbnail!(*size)
          elsif size.is_a?(String) && size =~ /^c.*$/ # Image cropping - example geometry string: c75x75
            dimensions = size[1..size.size].split("x")
            img.crop_resized!(dimensions[0].to_i, dimensions[1].to_i)
          else
            img.change_geometry(size.to_s) { |cols, rows, image|
              image.resize!(cols<1 ? 1 : cols, rows<1 ? 1 : rows)
            }
          end
          self.width  = img.columns if respond_to?(:width)
          self.height = img.rows    if respond_to?(:height)
          img = img.sharpen if attachment_options[:sharpen_on_resize] && img.changed?
          img.strip! unless attachment_options[:keep_profile]
          quality = img.format.to_s[/JPEG/] && get_jpeg_quality if quality.nil?
          data = img.to_blob do
            self.quality = quality if !quality.nil?
            self.density =  density if !density.nil?
            self.interlace = Magick::PlaneInterlace
            self.format = 'JPG'
          end
          self.temp_path = write_to_temp_file(data)
          self.size = File.size(self.temp_path)
        end
      end
    end
  end
end