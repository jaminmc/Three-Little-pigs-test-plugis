require 'optparse'
require 'yaml'
require 'ostruct'



# @todo want to make SiriProxy::Commandline without having to
# require 'siriproxy'. Im sure theres a better way.
class SiriProxy
    
end

class SiriProxy::CommandLine
  BANNER = <<-EOS
    Siri Proxy is a proxy server for Apple's Siri "assistant." The idea is to allow non Siri Capable Devices to connect.Welcome to The Three Little Pigs.
    
    See: https://github.com/jimmykane/The-Three-Little-Pigs-Siri-Proxy
    
    Usage: siriproxy COMMAND OPTIONS
    
    Commands:

    server            Start up the Siri proxy server
    gentables         Generate the tables for Database Siri
    gencerts          Generate a the certificates needed for SiriProxy
    bundle            Install any dependancies needed by plugins
    console           Launch the plugin test console 
    update [dir]      Updates to the latest code from GitHub or from a provided directory
    help              Show this usage information
    
    Options:

    Option                           Command    Description
  EOS
    
  def initialize
    @branch = nil
    parse_options
    command     = ARGV.shift
    subcommand  = ARGV.shift
    case command
    when 'server'           then run_server(subcommand)
    when 'gencerts'         then gen_certs
    when 'gentables'         then gen_tables  
    when 'bundle'           then run_bundle(subcommand)
    when 'console'          then run_console
    when 'update'           then update(subcommand)
    when 'help'             then usage
    else                    usage
    end
  end
    
  def run_console
    load_code
    $LOG_LEVEL = 0 
    # this is ugly, but works for now
    SiriProxy::PluginManager.class_eval do
      def respond(text, options={})
        puts "=> #{text}"
      end
      def process(text)
        super(text)
      end
      def send_request_complete_to_iphone
      end
      def no_matches
        puts "No plugin responded"
      end
    end
    SiriProxy::Plugin.class_eval do
      def last_ref_id
        0
      end
      def send_object(object, options={:target => :iphone})
        puts "=> #{object}"
      end
    end
    
    cora = SiriProxy::PluginManager.new
    repl = -> prompt { print prompt; cora.process(gets.chomp!) }
    loop { repl[">> "] }
  end
    
  def run_bundle(subcommand='')
    setup_bundler_path
    puts `bundle #{subcommand} #{ARGV.join(' ')}`
  end
    
  def run_server(subcommand='start')
    load_code
    start_server
    # @todo: support for forking server into bg and start/stop/restart
    # subcommand ||= 'start'
    # case subcommand
    # when 'start'    then start_server
    # when 'stop'     then stop_server
    # when 'restart'  then restart_server
    # end
  end
    
  def start_server
    proxy = SiriProxy.new
    proxy.start()
  end
    
  def gen_certs
    ca_name = @ca_name ||= ""
    command = File.join(File.dirname(__FILE__), '..', "..", "scripts", 'gen_certs.sh')
    sp_root = File.join(File.dirname(__FILE__), '..', "..")
    puts `#{command} "#{sp_root}" "#{ca_name}"`
  end
    
  def gen_tables
    require 'siriproxy/db_connection'
    if dbh=db_connect()
      puts "DATABASE FOUND"
    else 
      puts "Could not connect to database"
    end

    dbh.query("DROP TABLE IF EXISTS `keys`;")
    puts "Table keys Droped"

    dbh.query("CREATE TABLE `keys` (
  `id` int(100) unsigned NOT NULL AUTO_INCREMENT,
  `assistantid` longtext NOT NULL,
  `speechid` longtext NOT NULL,
  `sessionValidation` longtext NOT NULL,
  `expired` enum('False','True') NOT NULL DEFAULT 'False',
  `keyload` int(255) unsigned NOT NULL DEFAULT '0',
  `date_added` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;")  
    puts "Created Table keys"


    dbh.query("DROP TABLE IF EXISTS `config`;")
    puts "Table config Droped"


    dbh.query("CREATE TABLE `config` (
  `id` int(2) NOT NULL,
  `max_threads` int(5) unsigned NOT NULL DEFAULT '20',
  `max_connections` int(5) unsigned NOT NULL DEFAULT '100',
  `active_connections` int(5) unsigned NOT NULL DEFAULT '0',
  `max_keyload` int(5) unsigned NOT NULL DEFAULT '1000',
  `keyload_dropdown` int(5) unsigned NOT NULL,
  `keyload_dropdown_interval` int(5) unsigned NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;")
    puts "Created Table config"

    dbh.query("INSERT INTO `config` VALUES ('1', '20', '50', '7', '500', '50', '900');")
    puts "Added Default setting in Table config"
    
  end
    
    
    
  def update(directory=nil)
    if(directory)
      puts "=== Installing from '#{directory}' ==="
      puts `cd #{directory} && rake install`
      puts "=== Bundling ===" if $?.exitstatus == 0
      puts `siriproxy bundle` if $?.exitstatus == 0
      puts "=== SUCCESS ===" if $?.exitstatus == 0
    
      exit $?.exitstatus
    else
      branch_opt = @branch ? "-b #{@branch}" : ""
      @branch = "master" if @branch == nil
      puts "=== Installing latest code from git://github.com/jimmykane/The-Three-Little-Pigs-Siri-Proxy.git [#{@branch}] ==="
    
      tmp_dir = "/tmp/SiriProxy.install." + (rand 9999).to_s.rjust(4, "0")
    
      `mkdir -p #{tmp_dir}`
      puts `git clone #{branch_opt} git://github.com/jimmykane/The-Three-Little-Pigs-Siri-Proxy.git #{tmp_dir}`  if $?.exitstatus == 0
      puts "=== Performing Rake Install ===" if $?.exitstatus == 0
      puts `cd #{tmp_dir} && rake install`  if $?.exitstatus == 0
      puts "=== Bundling ===" if $?.exitstatus == 0
      puts `siriproxy bundle`  if $?.exitstatus == 0
      puts "=== Cleaning Up ===" and puts `rm -rf #{tmp_dir}` if $?.exitstatus == 0
      puts "=== SUCCESS ===" if $?.exitstatus == 0
    
      exit $?.exitstatus
    end 
  end
    
  def usage
    puts "\n#{@option_parser}\n"
  end
    
  private
    
  def parse_options
    $APP_CONFIG = OpenStruct.new(YAML.load_file(File.expand_path('~/.siriproxy/config.yml')))
    @branch = nil
    @option_parser = OptionParser.new do |opts|
      opts.on('-p', '--port PORT',     '[server]   port number for server (central or node)') do |port_num|
        $APP_CONFIG.port = port_num
      end
      opts.on('-l', '--log LOG_LEVEL', '[server]   The level of debug information displayed (higher is more)') do |log_level|
        $APP_CONFIG.log_level = log_level
      end
      opts.on('-b', '--branch BRANCH', '[update]   Choose the branch to update from (default: master)') do |branch|
        @branch = branch
      end
      opts.on('-n', '--name CA_NAME',  '[gencerts] Define a common name for the CA (default: "SiriProxyCA")') do |ca_name|
        @ca_name = ca_name
      end 
      opts.on('-host', '--db_host Hostname',  '[server] Define a host name for mysql (default: "localhost")') do |db_host|
        $APP_CONFIG.db_host = db_host
      end 
      opts.on('-U', '--db_user username',  '[server] Define a user name for mysql (default: "root")') do |db_user|
        $APP_CONFIG.db_user = db_user
      end 
      opts.on('-P', '--db_pass password',  '[server] Define a password for mysql (default: "password")') do |db_pass|
        $APP_CONFIG.db_pass = db_pass
      end 
      opts.on('-D', '--db_database database',  '[server] Define the database for mysql (default: "siri")') do |db_database|
        $APP_CONFIG.db_database = db_database
      end 
      opts.on_tail('-v', '--version',  '           show version') do
        require "siriproxy/version"
        puts "SiriProxy version #{SiriProxy::VERSION}"
        exit
      end
    end
    @option_parser.banner = BANNER
    @option_parser.parse!(ARGV)
  end
    
  def setup_bundler_path
    require 'pathname'
    ENV['BUNDLE_GEMFILE'] ||= File.expand_path("../../../Gemfile",
      Pathname.new(__FILE__).realpath)
  end
    
  def load_code
    setup_bundler_path
    
    require 'bundler'
    require 'bundler/setup'
    
    require 'siriproxy'
    require 'siriproxy/connection'
    require 'siriproxy/connection/iphone'
    require 'siriproxy/connection/guzzoni'
    require 'siriproxy/plugin'
    require 'siriproxy/plugin_manager'
    require 'siriproxy/db_classes'
    require 'siriproxy/db_connection'
  end
end