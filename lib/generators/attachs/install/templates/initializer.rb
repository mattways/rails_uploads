Attachs.configure do |config|

  config.fallback = 'missing.svg'
  config.convert_options = '-strip -quality 82'
  config.maximum_size = 5.megabytes

end
