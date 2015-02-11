#!/usr/bin/ruby

require 'inifile'
require 'fileutils'
require 'yaml'

class GitosisConfig
  class Group
    def initialize(conf, sect)
      @conf = conf
      @members = sect['members'].split
      @writable = sect['writable'] ? sect['writable'].split : []
      @readonly = sect['readonly'] ? sect['readonly'].split : []
    end

    def access?(repo, write)
      repos = @writable + (write ? [] : @readonly)
      return repos.include?(repo)
    end

    def member?(user)
      return @members.any? do |member|
        if md = /^@(\S+)/.match(member)
          group = @conf.groups[md[1]]
          group.member?(user)
        else
          member == user
        end
      end
    end
  end

  attr_reader :groups
  def initialize(conffile)
    ini = IniFile.load(conffile)

    @groups = {}
    ini.each_section do |name|
      md = /^group (\S+)/.match(name) or next
      groups[md[1]] = Group.new(self, ini[name])
    end
  end

  # Does a user have access to a repo?
  def access?(user, repo, write = false)
    @groups.values.any? do |group|
      group.access?(repo, write) && group.member?(user)
    end
  end
end


# Config file for gitosis2gitlab
class G2GConfig
  CONFFILE = 'gitosis2gitlab.yaml'

  attr_reader :gitlab_host, :gitlab_key, :gitlab_group, :dir_separator

  def initialize
    file = File.join(File.dirname(__FILE__), CONFFILE)
    @conf = YAML.load_file(file)

    @gitlab_group = @conf['group'] || 'imported'
    @dir_separator = @conf['separator'] || '-'
    @gitlab_key = @conf['key'] || '.ssh/id_rsa'

    @gitlab_host = @conf['host'] or raise "Need a host to connect to!"
  end

  def translate(repo)
    return gitlab_group + '/' + repo.gsub(%r{/}, Regexp.escape(dir_separator))
  end

  def gitosis_config
    return File.join(File.dirname(__FILE__), 'gitosis-admin')
  end
end


# Setup for use
def authorized_keys(config)
  # Generate authorized keys
  me = File.realpath($0)
  keys = File.join(config.gitosis_config, 'keydir', '*.pub')
  Dir[keys].each do |keyfile|
    user = File.basename(keyfile, '.pub')
    key = IO.read(keyfile).chomp
    puts "command=\"#{me}\ passthrough #{user}\"," +
      "no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty " +
      key
  end
end

# Pass through git commands to host
def passthrough(config, user)
  orig = ENV['SSH_ORIGINAL_COMMAND']
  md = %r{^(git-(?:receive|upload)-pack) '([\w./-]+)\.git'$}.match(orig) \
    or raise 'Bad command'
  command = md[1]
  repo = md[2]
  write = (command != 'git-upload-pack')

  conffile = File.join(config.gitosis_config, 'gitosis.conf')
  gitosis_config = GitosisConfig.new(conffile)
  gitosis_config.access?(user, repo, write) or raise "Access denied!"

  translated = config.translate(repo)
  run = ['ssh', '-i', config.gitlab_key, config.gitlab_host, command,
    translated + '.git']
  exec(*run)
end

def run(args)
  config = G2GConfig.new
  cmd = args.shift
  case cmd
    when 'authorized_keys'; authorized_keys(config)
    when 'passthrough'; passthrough(config, *args)
    else puts "Unknown command #{cmd}"
  end
end

run(ARGV)
