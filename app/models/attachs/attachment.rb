module Attachs
  class Attachment < ActiveRecord::Base

    STATES = %w(uploading processing processed)

    self.table_name = 'attachments'

    before_validation :ensure_requested_at, on: :create
    after_commit :delete_files, on: :destroy

    scope :attached, -> { where.not(attachable_id: nil) }
    scope :unattached, -> { where(attachable_id: nil) }
    scope :uploaded, -> { where.not(state: 'uploading') }
    scope :unprocessed, -> { where.not(state: 'processed') }

    STATES.each do |name|
      scope name, -> { where(state: name) }
    end

    belongs_to :attachable, polymorphic: true, required: false

    validates_presence_of :attachable_type, :attachable_attribute, :requested_at
    validate :attachable_type_must_be_valid, :attachable_attribute_must_be_valid
    validate :must_be_processed, if: :attached?

    with_options if: :processed? do |a|
      a.validates_presence_of :extension, :content_type, :size, :processed_at
      a.validates_numericality_of :size, greater_than: 0, only_integer: true
      a.validates_time_of :processed_at, after: :requested_at
    end

    STATES.each do |name|
      define_method "#{name}?" do
        state == name
      end
      define_method "#{name}!" do
        update! state: name
      end
    end

    def attached?
      attachable.present?
    end

    def unattached?
      !attached?
    end

    def unprocessed?
      !processed?
    end

    def uploaded?
      !uploading?
    end

    def default_path?
      options.has_key?(:default_path) || !configuration.default_path.nil?
    end

    def description
      if attached?
        key = "attachments.#{attachable_type.underscore}.#{attachable_attribute}"
        if I18n.exists?(key)
          I18n.t(key).gsub(/%\{[^\}]+\}/) do |match|
            interpolate match.remove(/%\{|\}/).to_sym
          end
        end
      end
    end

    def fetch(style=nil)
      if processed?
        style ||= :original
        if styles.include?(style)
          storage.fetch generate_path(style)
        end
      elsif persisted?
        storage.fetch key
      end
    end

    def url(style=nil)
      style ||= :original
      if styles.include?(style)
        if processed?
          storage.url generate_path(style)
        elsif default_path?
          storage.url generate_default_path(style)
        end
      end
    end

    def urls
      hash = {}
      if processed?
        generate_paths.each do |style, path|
          hash[style] = storage.url(path)
        end
      elsif default_path?
        styles.each do |style|
          path = generate_default_path(style)
          hash[style] = storage.url(path)
        end
      end
      hash
    end

    def process
      unless processed?
        file = fetch
        self.size = file.size
        self.content_type = Console.detect_content_type(file.path)
        self.extension = MIME::Types[content_type].first.extensions.first
        self.state = 'processed'
        self.processed_at = Time.zone.now
        configuration.callbacks.process :before_process, file, self
        storage.process file.path, generate_paths, content_type, style_options
        configuration.callbacks.process :after_process, file, self
        storage.delete key
        save
      end
    end

    def key
      prefix to_param
    end

=begin
    def reprocess
      if processed?
        upload = storage.fetch(current_paths[:original])
        new_paths = generate_paths
        (paths.values - new_paths.values).each do |path|
          self.old_paths |= [path]
        end
        (new_paths.values - paths.values).each do |path|
          storage.delete path
        end
        self.current_paths = new_paths
        storage.process upload.path, paths, content_type, style_optionss
        self.processed_at = Time.zone.now
        save
        attachable.touch
      end
    end

    def fix_missings
      if processed?
        missing_paths = {}
        paths.except(:original).each do |style, path|
          unless storage.exists?(path)
            missing_paths[style] = path
          end
        end
        if missing_paths.any?
          upload = storage.fetch(current_paths[:original])
          storage.process upload.path, missing_paths, content_type, style_options
          attachable.touch
        end
      end
    end
=end

    def saveable?
      persisted? || (changed - %w(attachable_id attachable_type attachable_attribute)).any?
    end
    alias_method :validable?, :saveable?

    def unsaveable?
      !saveable?
    end
    alias_method :unvalidable?, :unsaveable?

    def changed_for_autosave?
      if unsaveable?
        false
      else
        super
      end
    end

    def respond_to_missing?(name, include_private=false)
      extras.has_key?(name) || super
    end

    def method_missing(name, *args, &block)
      if extras.has_key?(name.to_s)
        extras[name.to_s]
      else
        super
      end
    end

    private

    %i(storage configuration).each do |name|
      define_method name do
        Attachs.send name
      end
    end

    def attachable_type_must_be_valid
      unless attachable_model.try(:attachable?)
        errors.add :attachable_type, :invalid
      end
    end

    def attachable_attribute_must_be_valid
      unless attachable_model.try(:has_attachment?, attachable_attribute)
        errors.add :attachable_attribute, :invalid
      end
    end

    def attachable_must_not_change
      # Needs work
      %w(attachable_id attachable_type attachable_attribute).each do |attribute|
        if send("#{attribute}_was").present? && send("#{attribute}_changed?")
          errors.add attribute, :immutable
        end
      end
    end

    def must_be_processed
      unless processed?
        errors.add :base, :unprocessed
      end
    end

    def delete_files
      if processed?
        styles.each do |style|
          storage.delete path(style)
        end
      end
    end

    def attachable_model
      if attachable_type.present?
        attachable_type.classify.safe_constantize
      end
    end

    def options
      if attachable_model.present? && attachable_attribute.present?
        attachable_model.attachments[attachable_attribute.to_sym]
      else
        {}
      end
    end

    def style_options
      options.fetch :styles, {}
    end

    def styles
      [:original] + options.fetch(:styles, {}).keys
    end

    def generate_default_path(style)
      path = (options[:default_path] || configuration.default_path)
      prefix path.gsub(':style', style.to_s)
    end

    def generate_path(style)
      prefix "#{to_param}/#{ofuscate(style).dasherize}" + ".#{extension}"
    end

    def prefix(path)
      if value = configuration.prefix.try(:remove, /^\//)
        "#{value}/#{path}"
      else
        path
      end
    end

    def generate_paths
      hash = {}
      styles.each do |style|
        hash[style] = generate_path(style)
      end
      hash
    end

    def ofuscate(value)
      alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789'
      encoding = '8kluw1mtri2xncsp649obvezgd57qy3fj0ah'
      value.to_s.tr alphabet, encoding
    end

    def ensure_requested_at
      self.requested_at ||= Time.zone.now
    end

    def interpolate(name)
      if configuration.interpolations.exists?(name)
        configuration.interpolations.process name, attachable
      elsif attachable.respond_to?(name)
        attachable.send name
      end
    end

    class << self

      def clear
        unattached.where('request_at < ?', (Time.zone.now - 1.day)).find_each &:destroy
      end

      %i(reprocess fix_missings).each do |name|
        define_method name do
          processed.find_each do |attachment|
            attachment.send name
          end
        end
      end

      private

      def storage
        Attachs.storage
      end

    end
  end
end
