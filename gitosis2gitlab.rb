#!/usr/bin/ruby

HOST = 'gitlab.ewdev.ca'
USER = 'git'
SSH_KEY = '.ssh/id_rsa'
GITOSIS_CONFIG = 'gitosis-admin'
GITLAB_GROUP = 'imported'

# Translate gitosis repo name to gitlab repo name
def translate_repo(repo, group)
  return group + '/' + repo.gsub(%r{/}, '-')
end


require 'inifile'
require 'fileutils'

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

# Setup for use
def authorized_keys
  # Generate authorized keys
  me = File.realpath($0)
  keys = File.join(GITOSIS_CONFIG, 'keydir', '*.pub')
  Dir[keys].each do |keyfile|
    user = File.basename(keyfile, '.pub')
    key = IO.read(keyfile).chomp
    puts "command=\"#{me}\ #{user}\"," +
      "no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty " +
      key
  end
end

# Pass through git commands to host
def passthrough(user)
  orig = ENV['SSH_ORIGINAL_COMMAND']
  md = %{^(git-(?:receive|upload)-pack) '([\d./-])'$}.match(orig) \
    or raise 'Bad command'
  command = md[1]
  repo = md[2]
  write = (command != 'git-receive-pack')

  config = GitosisConfig.new(GITOSIS_CONFIG)
  config.access?(user, repo, write) or raise "Access denied!"

  translated = translate_repo(repo, GITLAB_GROUP)
  exec('ssh', '-i', SSH_KEY, '-l', USER, HOST, command, translated)
end

def run(args)
  cmd = args.shift
  case cmd
    when 'authorized_keys'; authorized_keys
    when 'passthrough'; passthrough(*args)
    else puts "Unknown command #{cmd}"
  end
end

run(ARGV)
