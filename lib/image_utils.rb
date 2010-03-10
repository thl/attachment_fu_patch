module ImageUtils
  # Custom resizing of image which crops if necessary.
  # Size is a string in the following format: [Quality]:[Width]x[Height][>|#]
  # Returns the quality part of size to be used when saving.
  def ImageUtils.resize_image(image, size)
    pos = size.index(':')
    quality = nil
    if !pos.nil?
      quality = size[0...pos].to_i
      size = size[pos+1...size.size]
    end
    if size[size.size-1]==35 # numeral sign
      size.downcase!
      pos = size.index('x')
      image.crop_resized!(size[0...pos].to_i, size[pos+1...size.size-1].to_i)
    else            
      image.change_geometry(size.to_s) { |cols, rows, image| image.resize!(cols<1 ? 1 : cols, rows<1 ? 1 : rows) }
    end
    return quality
  end
  
  def resize_image(image, size)
    ImageUtils.resize_image(image, size)
  end
end