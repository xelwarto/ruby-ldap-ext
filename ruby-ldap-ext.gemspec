
$:.push File.expand_path("lib", File.dirname(__FILE__))
require 'ext/ldap/version'

Gem::Specification.new do |spec|
  spec.name         = Ext::LDAP::NAME
  spec.version      = Ext::LDAP::VERSION
  spec.summary      = 'Extened Ruby net-ldap library'
  spec.description  = 'Extened Ruby net-ldap library'
  spec.licenses     = ['Apache-2.0']
  spec.platform     = Gem::Platform::RUBY
  spec.authors      = ['Ted Elwartowski']
  spec.email        = ['xelwarto.pub@gmail.com']
  spec.homepage     = 'https://github.com/xelwarto/ruby-ldap-ext'
  
  spec.required_ruby_version  = '>= 1.9.3'
  
  spec.add_dependency 'net-ldap', '~> 0.8'

  files = []
  dirs = %w{lib}
  dirs.each do |dir|
    files += Dir["#{dir}/**/*"]
  end
  
  files << "LICENSE"
  spec.files = files
  spec.require_paths << 'lib'  
end
