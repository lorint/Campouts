require 'yaml'
module Repository
  # So we know when we've got everything ready
  @@to_be_loaded = {}
  @@to_be_has_many = Hash.new { [] }
  @@to_be_belongs_to = []
  @@classes_loaded = []

  # Find all additional classes referenced by a given YAML file
  def self.find_yaml_dependencies(children, classes = {})
    if children
      children.each do |sequence|
        if sequence.tag
          if sequence.tag.start_with?("!ruby/object:")
            classes[sequence.tag[13..-1]] = nil
          end
        end
        find_yaml_dependencies(sequence.children, classes)
      end
    end
    classes
  end

  def self.included(base)
    base.extend(ClassMethods)
    base.all = []

    # Load what we can, and put the names of what we can't load in @@to_be_loaded
    filename = base.name.downcase
    if File.exists? "#{filename}.yml"
      required_classes = Repository.find_yaml_dependencies(YAML.parse_file "#{filename}.yml")
      # Remove the class names that are already loaded
      required_classes.keys.each do |klass|
        if Object.const_defined?(klass)
          required_classes.delete(klass)
        end
      end
      if required_classes.empty?
        puts "Loading #{filename}.yml"
        self.load_class(base, filename)
      else
        puts "Deferring #{filename}.yml until #{required_classes.keys.join(", ")} is loaded"
        @@to_be_loaded[base.name] = required_classes.keys
      end
    else
      puts "Class #{base.name} is available"
      @@classes_loaded << base
    end
    @@to_be_loaded.each do |k, v|
      if (v -= [base.name]).empty?
        filename = k.downcase
        puts "Now loading #{filename}.yml"
        klass = Object.const_get(k)
        self.load_class(klass, filename)
        @@to_be_loaded.delete(k)
      end
    end
    param_sets = @@to_be_has_many[base.name]
    if param_sets
      param_sets.each do |params|
        puts "Now doing #{params[:primary_class].name} has_many :#{params[:foreign_symbol]}"
        Repository::ClassMethods.build_has_many params
      end
      @@to_be_has_many.delete(base.name)
    end

    # We don't know whether our base class or YAML will go away first
    @is_saved_at_end = false
    end_saver = proc do
      unless @is_saved_at_end
        puts "Saving #{@@classes_loaded.map(&:name).join(", ")}"
        @@classes_loaded.each do |klass|
          klass.save_all
        end
        @is_saved_at_end = true
      end
    end
    ObjectSpace.define_finalizer(base, end_saver)
    ObjectSpace.define_finalizer(YAML, end_saver)
    ObjectSpace.define_finalizer(File, end_saver)

    class << base
      # Make it so new objects automatically get added to our entries
      # C
      alias_method :__new, :new
      def new(*args)
        new_thing = __new()
        new_thing.update(*args) if args.length == 1
        self.all << new_thing
        new_thing
      end
    end
  end

  def self.load_class(klass, filename)
    klass.all = YAML.load_file "#{filename}.yml"
    @@classes_loaded << klass
    class_name = klass.name
    @@to_be_belongs_to.select {|tbbt|
      @@classes_loaded.map(&:name).include?(tbbt[:primary_class_name]) &&
      @@classes_loaded.include?(tbbt[:foreign_class])
    }.each do |tbbt|
      Repository::ClassMethods.associate_belongs_to(tbbt)
      @@to_be_belongs_to.delete(tbbt)
    end
  end

  module ClassMethods
    def count
      @entries.count
    end

    def save_all
      file = File.open("#{self.name.downcase}.yml", "w")
      file.write(self.all.to_yaml)
      file.close
    end

    # R - read
    def all
      @entries
    end

    def all=(entries)
      @entries = entries
    end

    def where(params)
      @entries.select do |entry|
        params.all? do |k, v|
          entry.send(k) == v
        end
      end
    end

    def find_by(params)
      self.where(params).first
    end

    # Some cool methods that add other methods for relationships!
    def has_many(foreign, options = {})
      # Find class name by "singularizing" the plural foreign name
      # by simply dropping the last letter if it's "s", or by looking
      # for a :singular entry in any incoming options.
      foreign_class_name = nil
      if options[:singular].nil?
        foreign_class_snake_name = foreign.to_s.end_with?("s") ? foreign.to_s[0..-2] : foreign.to_s
      else
        foreign_class_snake_name = options[:singular].to_s
      end
      foreign_class_name = foreign_class_snake_name.split("_").map(&:capitalize).join
      primary_snake_name = self.name.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
      has_many_params = {foreign_class_name: foreign_class_name, foreign_symbol: foreign, primary_class: self, primary_snake_name: primary_snake_name}
      if Object.const_defined?(foreign_class_name)
        puts "#{self.name} has many #{foreign.to_s}"
        Repository::ClassMethods.build_has_many has_many_params
      else
        puts "Deferring #{self.name} has_many :#{foreign}"
        to_be_has_many = Repository.class_variable_get :@@to_be_has_many
        to_be_has_many[foreign_class_name] += [has_many_params]
      end
    end

    def self.build_has_many(params)
      foreign_class = Object.const_get(params[:foreign_class_name])

      # Put an instance method in the class for the has_many
      # In here self is the class our mixin is being included upon.
      primary_class = params[:primary_class]
      primary_class.send(:define_method, params[:foreign_symbol]) do
        # In this self means the object that relates as 1:m to foreign things
        foreign_class.where(params[:primary_snake_name].to_sym => self)
      end
    end

    def belongs_to(primary, options = nil)
      puts "#{self.name}s belong to #{primary.to_s}"
      # For associating related foreign objects
      primary_class_name = primary.to_s.split("_").map(&:capitalize).join
      belongs_to_params = {foreign_class: self, primary_method_name: primary, primary_class_name: primary_class_name}
      classes_loaded = Repository.class_variable_get :@@classes_loaded
      if classes_loaded.map(&:name).include?(primary_class_name) &&
          classes_loaded.include?(self)
        puts "Associating #{self.name} to #{primary_class_name} STRAIGHTAWAY"
        Repository::ClassMethods.associate_belongs_to belongs_to_params
      else
        puts "Deferring association of #{self.name} to #{primary_class_name}"
        to_be_belongs_to = Repository.class_variable_get :@@to_be_belongs_to
        to_be_belongs_to << belongs_to_params
      end
      attr_accessor primary.to_sym
    end

    def self.associate_belongs_to(params)
      primary_class_name = params[:primary_class_name]
      primary_method_name = params[:primary_method_name].to_s
      foreign_class = params[:foreign_class]
      primary_all = Object.const_get(primary_class_name).all
      # For each related thing, try to associate
      count = 0
      foreign_class.all.each do |foreign_object|
        original = primary_all.find{|primary_object| primary_object == foreign_object.send(primary_method_name)}
        unless original.nil?
          foreign_object.send(primary_method_name + "=", original)
          count += 1
        end
      end
      puts "Associated #{count} #{foreign_class.name}s to #{primary_class_name}s"
    end
  end

  # Override the normal equality test
  def ==(other)
    self.instance_variables.all? do |var|
      self.instance_variable_get(var) == other.instance_variable_get(var)
    end
  end

  # U
  def update(params)
    params.each do |k, v|
      self.send(k.to_s + "=", v)
    end
    self
  end

  # D
  def destroy
    self.class.all.delete_at(self.class.all.index(self))
    self
  end
end
