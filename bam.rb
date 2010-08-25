#!/usr/bin/env ruby
require 'socket'
require 'timeout'
# require File.join(File.dirname(__FILE__), "../urty", "urbanterror.rb")
require 'rubygems'
require 'urbanterror'

class UrtBot
  def initialize(nick,channels,server,port=6667)
    @channels = channels
    @socket = TCPSocket.open(server, port)
    @socket.puts "NICK #{nick}"
    @socket.puts "USER #{nick} #{nick} #{nick} #{nick}"
    @host_aliases = {
      'mn' => 'mostlynothing.info',
      'mi' => 'mostlyincorrect.info',
      'e' => 'elrod.me',
    }
  end
  
  def privmsg(channel, message)
    @socket.puts "PRIVMSG #{channel} :#{message}"
  end
  
  def urt_info(host, port)
    begin
      Timeout::timeout 5 do
        urt = UrbanTerror.new(host, port.to_i)
        settings = urt.settings
        players = urt.players.sort_by { |player| -player[:score] }
        playersinfo = []
        players.each do |player|
          player[:ping] = "#{3.chr}04#{player[:ping]}#{3.chr}" if player[:ping] == 999
          playersinfo << "#{player[:name].gsub(/ +/, ' ')} (Ping: #{player[:ping]}, Score: #{player[:score]})"
        end
        return "Current map: #{2.chr}#{settings['mapname']}#{2.chr} (#{UrbanTerror.matchType(settings['g_gametype'].to_i, true)}). Players: #{playersinfo.join(', ')}"
      end
    rescue Timeout::Error
      return "A timeout occured."
    rescue
      return "An error has occured. Check your syntax and try again."
    end
  end

  def handle(nick,ident,cloak,channel,message)
    case message.strip
    when /^\.urt (.*)/
      hosts = $1.split(';')
      alreadyused = []
      hosts.each do |host|
        alreadyused << host
        if not alreadyused.include? host
          hostname, port = host.split(':', 2)
          port = port.to_i
          port = 27960 if port.zero?
          hostname = @host_aliases[hostname] if @host_aliases.has_key? hostname
          if host.empty?
            privmsg(channel, "#{nick}: Use .urt hostname[:port]")
          else
            privmsg(channel, urt_info(hostname, port))
          end
        end
      end
    end
  end
  
  def run
    while line = @socket.gets
      puts line
      case line
      when /^:[\w.-]+ 001/
        # Join channels
        @channels.each do |channel|
          @socket.puts "JOIN #{channel}"
        end
      when /PING :(.*)/
        @socket.puts "PONG :#{$1}}"
      when /^:(.*)!(.*)@(.*) PRIVMSG (.*) :(.*)/
        handle($1,$2,$3,$4,$5)
      end
    end
  end
end

bot = UrtBot.new('bam2', ['#offtopic','#bots','#programming'], 'irc.ninthbit.net')
bot.run
