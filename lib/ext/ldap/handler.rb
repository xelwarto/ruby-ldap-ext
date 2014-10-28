
module Ext
  module LDAP
    class Handler
      include Singleton
      
      def initialize
        config = Ext::LDAP.config

        @host       = config.host
        @port       = config.port
        @secure     = config.secure
        @username   = config.bind_dn
        @password   = config.bind_pass

        @timeout    = config.timeout
        @base       = config.base
        @ldap       = nil
      end
      
      # Start Public Methods
      
      ##############
      # Method: user_from_uid
      def user_from_uid(opts=nil,&block)
        raise Ext::LDAP::Error.new('method parameters are invalid') if opts.nil?
        raise Ext::LDAP::Error.new('method parameter type is incorrect - requires Hash') if !opts.instance_of? Hash
        raise Ext::LDAP::Error.new('required parameter(uid) is invalid') if opts[:uid].nil?
        
        if opts[:attributes].nil?
          opts[:attributes] = ['uid']
        else
          raise Ext::LDAP::Error.new('parameter(attributes) type is incorrect - requires Array') if !opts[:attributes].instance_of? Array
        end
        
        if opts[:base].nil?
          opts[:base] = @base
        end
        
        filter = Net::LDAP::Filter.eq :uid, opts[:uid]
        search base: opts[:base], filter: filter, attributes: opts[:attributes], &block
      end
      
      ##############
      # Method: user_from_dn
      def user_from_dn(opts=nil,&block)
        raise Ext::LDAP::Error.new('method parameters are invalid') if opts.nil?
        raise Ext::LDAP::Error.new('method parameter type is incorrect - requires Hash') if !opts.instance_of? Hash
        raise Ext::LDAP::Error.new('required parameter(dn) is invalid') if opts[:dn].nil?
        
        if opts[:attributes].nil?
          opts[:attributes] = ['uid']
        else
          raise Ext::LDAP::Error.new('parameter(attributes) type is incorrect - requires Array') if !opts[:attributes].instance_of? Array
        end
        
        filter = Net::LDAP::Filter.eq :objectClass, 'person'
        search base: opts[:dn], filter: filter, attributes: opts[:attributes], &block
      end
      
      ##############
      # Method: user_from_mail
      def user_from_mail(opts=nil,&block)
        raise Ext::LDAP::Error.new('method parameters are invalid') if opts.nil?
        raise Ext::LDAP::Error.new('method parameter type is incorrect - requires Hash') if !opts.instance_of? Hash
        raise Ext::LDAP::Error.new('required parameter(mail) is invalid') if opts[:mail].nil?
        
        if opts[:attributes].nil?
          opts[:attributes] = ['uid']
        else
          raise Ext::LDAP::Error.new('parameter(attributes) type is incorrect - requires Array') if !opts[:attributes].instance_of? Array
        end
        
        if opts[:base].nil?
          opts[:base] = @base
        end
        
        filter = Net::LDAP::Filter.eq :mail, opts[:mail]
        search base: opts[:base], filter: filter, attributes: opts[:attributes], &block
      end
      
      ##############
      # Method: search
      def search(opts=nil)
        @ldap ||= connect
        raise Ext::LDAP::Error.new('LDAP connection is invalid') if @ldap.nil?
        
        raise Ext::LDAP::Error.new('method parameters are invalid') if opts.nil?
        raise Ext::LDAP::Error.new('method parameter type is incorrect - requires Hash') if !opts.instance_of? Hash
        
        raise Ext::LDAP::Error.new('required parameter(filter) is invalid') if opts[:filter].nil?
        
        if opts[:attributes].nil?
          opts[:attributes] = ['uid']
        else
          raise Ext::LDAP::Error.new('parameter(attributes) type is incorrect - requires Array') if !opts[:attributes].instance_of? Array
        end

        if opts[:base].nil?
          opts[:base] = @base
        end
        
        if opts[:timeout].nil?
          opts[:timeout] = @timeout
        end
        
        Timeout::timeout(opts[:timeout]) do
          @ldap.open do |l|
            results = l.search base: opts[:base], filter: opts[:filter], attributes: opts[:attributes], return_result: true

            if l.get_operation_result.code > 0
              if !block_given?
                return nil
              end
            else
              if !results.nil? && results.any?
                if block_given?
                  results.each do |ent|
                    yield LdapResult.new(l,ent)
                  end
                else
                  return LdapResult.parse @ldap, results
                end
              else
                return nil
              end
            end
          end
        end
      end
      
      # End Public Methods
      
      private
      
      # Start Private Methods
      
      ##############
      # Method: connect
      def connect
        ldap = nil

        auth = {
          :method => :simple,
          :username => @username,
          :password => @password }
        ldap = Net::LDAP.new :host => @host, :port => @port, :auth => auth

        if @secure
          ldap.encryption :simple_tls
        end

        Timeout::timeout(@timeout) do
          result = ldap.bind

          if result.nil? || ldap.get_operation_result.code > 0
            ldap = nil
          end
        end

        ldap
      end
      
      # End Private Methods
      
      # Start Class LdapResult
      
      class LdapResult
        attr_accessor :ops

        def initialize(ldap, ent=nil)
          @ldap = ldap
          @ops = []
          
          if ent.nil?
            @entity = Net::LDAP::Entry.new
          else
            @entity = ent
          end
        end

        def dn
          @entity.dn
        end

        def dn=(dn)
          @entity[:dn] = dn
        end

        def attributes
          @entity.attribute_names
        end

        def to_ldif
          @entity.to_ldif
        end

        def get(name)
          @entity[name.to_sym]
        end

        def first(name)
          return nil if @entity[name.to_sym].nil? || !@entity[name.to_sym].any?
          @entity[name.to_sym].first
        end

        def clear_ops
          @ops = []
        end

        def update!
          result = update @ops
          result ||= false

          if result
            @ops.each do |o|
              act = o.shift
              name = o.shift
              if act == :add || act == :replace
                value = o.shift
                _update name, value
              else
                _delete name
              end
            end

            @ops = []
          end

          result
        end

        def update(ops=[])
          result = nil
          
          if !ops.empty?
            result = @ldap.modify dn: self.dn, operations: ops

            if @ldap.get_operation_result.code > 0
              result = nil
            end
          end

          result ||= false
        end

        def add(name, value)
          @ops.push([ :add, name.to_sym, value ])
        end

        def add!(name,value)
          result = nil

          result = @ldap.add_attribute self.dn, name.to_sym, value

          if @ldap.get_operation_result.code > 0
            result = nil
          else
            _update name, value
          end

          result ||= false
        end

        def replace(name, value)
          @ops.push([ :replace, name.to_sym, value ])
        end

        def replace!(name,value)
          result = nil

          result = @ldap.replace_attribute self.dn, name.to_sym, value

          if @ldap.get_operation_result.code > 0
            result = nil
          else
            _update name, value
          end

          result ||= false
        end

        def delete(name)
          @ops.push([ :delete, name.to_sym ])
        end

        def delete!(name)
          result = nil

          result = @ldap.delete_attribute self.dn, name.to_sym

          if @ldap.get_operation_result.code > 0
            result = nil
          else
            _update name, value
          end

          result ||= false
        end

        def self.parse(ldap,res=nil)
          results = nil

          if !res.nil? && res.any?
            results = res.map { |r| LdapResult.new(ldap,r) }
          end

          results
        end

        private

        def _update(name, value)
          @entity[name.to_sym] = value
        end

        def _delete(name)
          @entity[name.to_sym] = []
        end
      end
  
      # End Class LdapResult
    end
  end
end

