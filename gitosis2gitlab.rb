#!/usr/bin/ruby
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

  # Parse a .ini format file
  def self.ini_parse(io, &block)
    name = nil
    contents = {}

    io.each do |line|
      if md = /^\[(.*)\]$/.match(line)
        # Yield the old section
        yield name, contents if name

        # Start a new section
        name = md[1]
        contents = {}
      elsif md = /^(\w+)\s*=\s*(.*)/.match(line)
        contents[md[1]] = md[2]
      end
    end
    yield name, contents if name
  end

  attr_reader :groups
  def initialize(conffile)
    @groups = {}
    open(conffile) do |f|
      self.class.ini_parse(f) do |name, section|
        md = /^group (\S+)/.match(name) or next
        groups[md[1]] = Group.new(self, section)
      end
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

  def gitosis_admin
    return File.join(File.dirname(__FILE__), 'gitosis-admin')
  end
  def gitosis_config
    return GitosisConfig.new(File.join(gitosis_admin, 'gitosis.conf'))
  end
end


# Setup for use
def authorized_keys(config)
  # Generate authorized keys
  me = File.realpath($0)
  keys = File.join(config.gitosis_admin, 'keydir', '*.pub')
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

  gitosis_config = config.gitosis_config
  gitosis_config.access?(user, repo, write) or raise "Access denied!"

  translated = config.translate(repo)
  run = ['ssh', '-i', config.gitlab_key, config.gitlab_host, command,
    translated + '.git']
  exec(*run)
end

# Check if a user has access to a repository
def test_membership(config, user, repo, writable = nil)
  gitosis_config = config.gitosis_config
  if gitosis_config.access?(user, repo, writable)
    puts "Access granted"
    exit 0
  else
    puts "Access denied!"
    exit -1
  end
end

def run(args)
  config = G2GConfig.new
  cmd = args.shift
  case cmd
    when 'access'; test_membership(config, *args)
    when 'authorized_keys'; authorized_keys(config)
    when 'passthrough'; passthrough(config, *args)
    else puts "Unknown command #{cmd}"
  end
end

run(ARGV)
