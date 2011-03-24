require 'dm-core'
require 'dm-validations'
require 'dm-is-remixable'
require 'dm-accepts_nested_attributes'

require 'dm-is-localizable/language'

module DataMapper
  module I18n

    DEFAULT_LANGUAGE_CODE = 'en-US'

    def self.default_language=(code)
      @default_language = Language[code]
    end

    def self.default_language
      @default_language ||= Language[DEFAULT_LANGUAGE_CODE]
    end

    def self.default_language_code
      default_language.code
    end

    module Model

      module Translation
        include DataMapper::Resource
        is :remixable
        property :id, Serial
      end

      def is_localizable(options = {}, &block)

        extend  ClassMethods
        include InstanceMethods

        options = {
          :as                       => nil,
          :model                    => "#{self}Translation",
          :accept_nested_attributes => true
        }.merge(options)

        remixer_fk  = DataMapper::Inflector.foreign_key(self.name).to_sym
        remixer     = remixer_fk.to_s.gsub('_id', '').to_sym
        demodulized = DataMapper::Inflector.demodulize(options[:model].to_s)
        remixee     = DataMapper::Inflector.tableize(demodulized).to_sym

        remix n, Translation, :as => options[:as], :model => options[:model]

        @translation_model = DataMapper::Inflector.constantize(options[:model])

        enhance :translation, @translation_model do

          property remixer_fk,   Integer, :min => 1, :required => true, :unique_index => :unique_languages
          property :language_id, Integer, :min => 1, :required => true, :unique_index => :unique_languages

          belongs_to remixer
          belongs_to :language

          class_eval &block

          validates_uniqueness_of :language_id, :scope => remixer_fk

        end

        has n, :languages, :through => remixee, :constraint => :destroy

        self.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)

          alias :translations :#{remixee}

          if options[:accept_nested_attributes]

            # cannot accept_nested_attributes_for :translations
            # since this is no valid relationship name, only an alias

            accepts_nested_attributes_for :#{remixee}
            alias :translations_attributes :#{remixee}_attributes

          end

        RUBY

        localizable_properties.each do |property_name|
          self.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)

            def #{property_name}(language_code = DataMapper::I18n.default_language_code)
              translate(:#{property_name.to_sym}, Language.normalized_code(language_code))
            end

          RUBY
        end

      end

      module ClassMethods

        def translation_model
          @translation_model
        end

        # list all available languages for the localizable model
        def available_languages
          ids = translation_model.all.map { |t| t.language_id }.uniq
          ids.any? ? Language.all(:id => ids) : []
        end

        # the number of all available languages for the localizable model
        def nr_of_available_languages
          available_languages.size
        end

        # checks if all localizable resources are translated in all available languages
        def translations_complete?
          available_languages.size * all.size == translation_model.all.size
        end

        # returns a list of symbols reflecting all localizable property names of this resource
        def localizable_properties
          translation_model.properties.map { |p| p.name } - non_localizable_properties
        end

        # returns a list of symbols reflecting the names of all the
        # not localizable properties in the remixed translation_model
        def non_localizable_properties
          [ :id, :language_id, DataMapper::Inflector.foreign_key(self.name).to_sym ]
        end

      end # module ClassMethods

      module InstanceMethods

        # list all available languages for this instance
        def available_languages
          ids = translations.map { |t| t.language_id }.uniq
          ids.any? ? Language.all(:id => ids) : []
        end

        # the number of all available languages for this instance
        def nr_of_available_languages
          available_languages.size
        end

        # checks if this instance is translated into all available languages for this model
        def translations_complete?
          self.class.nr_of_available_languages == translations.size
        end

        # translates the given attribute to the language identified by the given language_code
        def translate(attribute, language_code)
          if language = Language[language_code]
            t = translations.first(:language_id => language.id)
            t.respond_to?(attribute) ? t.send(attribute) : nil
          else
            nil
          end
        end

      end # module InstanceMethods

    end # module Model
  end # module I18n

  Model.append_extensions I18n::Model

end # module DataMapper

