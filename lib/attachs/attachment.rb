module Attachs
  class Attachment

    attr_reader :record, :attribute, :filename, :content_type, :size, :updated_at, :upload, :options

    delegate :basename, :extension, :image?, :url, :process, :destroy, :update, to: :type

    def initialize(record, attribute, options, source=false)
      @record = record
      @attribute = attribute
      @options = options
      if source
        @upload = source
        @filename = source.original_filename.downcase
        @content_type = source.content_type
        @size = source.size
        @updated_at = Time.zone.now
        %w(filename content_type size updated_at).each do |name|
          record.send "#{attribute}_#{name}=", send(name)
        end
      elsif source == nil
        %w(filename content_type size updated_at).each do |name|
          record.send "#{attribute}_#{name}=", nil
        end
      elsif source == false
        %w(filename content_type size updated_at).each do |name|
          instance_variable_set :"@#{name}", record.send("#{attribute}_#{name}")
        end
      end
    end

    def styles
      @styles ||= ((options[:styles] || []) | Attachs.config.global_styles)
    end

    def private?
      @private ||= options[:private] == true
    end

    def public?
      !private?
    end

    def upload?
      !upload.nil?
    end

    def processed?
      !upload? and exists?
    end

    def exists?
      filename and size and content_type and updated_at
    end

    def blank?
      !exists?
    end

    def default?
      !options[:default_path].nil?
    end

    protected

    def type
      @type ||= begin
        if exists?
          Attachs::Types::Regular.new(self)
        else
          Attachs::Types::Default.new(self)
        end
      end
    end

  end
end
