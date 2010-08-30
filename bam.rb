#!/usr/bin/env ruby
require 'socket'
require 'timeout'
# require File.join(File.dirname(__FILE__), "../urty", "urbanterror.rb")
require 'rubygems'
require 'urbanterror'

class UrtBot
  def initialize(nick,channels,server,port=6667)
    @botnick = nick
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
        if players.count != 0
          players.each do |player|
            player[:name] = "#{3.chr}04#{player[:name]}#{3.chr}" if player[:ping] == 999
            playersinfo << "#{player[:name].gsub(/ +/, ' ')} (#{player[:score]})"
          end
          players = playersinfo.join(', ')
        else
          players << "None."
        end
        weapons = UrbanTerror.reverseGearCalc(settings['g_gear'].to_i)
        weapons = weapons.size == 6 ? 'all weapons' : weapons.join(', ')
        gametype = UrbanTerror.matchType(settings['g_gametype'].to_i, true)
        
        "Map: #{2.chr}#{settings['mapname']}#{2.chr} (#{gametype} w/ #{weapons}). Players: #{players}"
      end
    rescue Timeout::Error
      "A timeout occured."
    rescue
      "An error has occured. Check your syntax and try again."
    end
  end
  
  def reply(message)
    privmsg(@channel, "#{@nick}: #{message}")
  end

  def handle(nick,ident,cloak,channel,message)
    case message.strip
    when /^\.urt (.*)/
      hosts = $1.split(';')
      alreadyused = []
      hosts.each do |host|
        if not alreadyused.include? host
          hostname, port = host.split(':', 2)
          port = port.to_i
          port = 27960 if port.zero?
          hostname = @host_aliases[hostname] if @host_aliases.has_key? hostname
          if host.empty?
            reply "Use .urt hostname[:port]"
          else
            reply urt_info(hostname, port)
          end
          alreadyused << host
        end
      end
    when /^\.gear (.*)/
      origline = $1
      begin
        if origline =~ /^-?\d+$/
          weapons = UrbanTerror.reverseGearCalc(origline.to_i).join(', ')
          reply "#{weapons}"
        else
          number = UrbanTerror.gearCalc(origline.gsub(' ','').split(','))
          reply "#{number}"
        end
      rescue => error
        reply "#{error.message}"
      end
    end
  end
  
  def run
    while line = @socket.gets
      puts line
      case line
      when /^:[\w.-]+ 433/
        @socket.puts "NICK #{@botnick}#{rand 100}"
      when /^:[\w.-]+ 001/
        # Join channels
        @channels.each do |channel|
          @socket.puts "JOIN #{channel}"
        end
      when /PING :(.*)/
        @socket.puts "PONG :#{$1}}"
      when /^:(.*)!(.*)@(.*) PRIVMSG (.*) :(.*)/
        @nick, @ident, @cloak, @channel, @message = $1, $2, $3, $4, $5
        handle($1,$2,$3,$4,$5)
      end
    end
  end
end

bot = UrtBot.new('bam', ['#offtopic','#bots','#programming'], 'jade.ninthbit.net', 6664)
bot.run
