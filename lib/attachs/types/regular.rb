module Attachs
  module Types
    class Regular < Base

      delegate :url, :process, :destroy, to: :storage

      def basename
        @basename ||= File.basename(attachment.filename, ".#{extension}")
      end

      def extension
        @extension ||= File.extname(attachment.filename).from(1)
      end

      def image?
        @image ||= attachment.content_type.start_with?('image')
      end

    end
  end
end
