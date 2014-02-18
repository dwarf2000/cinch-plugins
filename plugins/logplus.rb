# -*- coding: utf-8 -*-
#
# = Cinch advanced message logging plugin
# Fully-featured logging module for cinch with both
# plaintext and HTML logs.
#
# == Configuration
# None
#
# == Author
# Marvin Gülker (Quintus)
#
# == License
# An advanced logging plugin for Cinch.
# Copyright © 2014 Marvin Gülker
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

class Cinch::LogPlus
  include Cinch::Plugin

  set :required_options, [:plainlogdir, :htmllogdir]

  listen_to :connect,    :method => :startup
  listen_to :channel,    :method => :log_public_message
  timer 5,              :method => :check_midnight

  DEFAULT_CSS = <<-CSS
    <style type="text/css">
    body {
       background-color: white;
    }
    .chattable {
        border-collapse: collapse;
     }
    .msgnick {
        border-right: 1px solid black;
        padding-right: 8px;
        padding-left: 4px;
    }
    .opped {
        color: #006e21;
        font-weight: bold;
     }
     .halfopped {
        color: #006e21;
     }
    .voiced {
        color: #00a5ff;
        font-style: italic;
     }
    .msgmessage {
        padding-left: 8px;
    }
    </style>
  CSS

  def startup(*)
    @plainlogdir = config[:plainlogdir]
    @htmllogdir  = config[:htmllogdir]
    @timelogformat = config[:timelogformat] = "%H:%M"
    @extrahead = config[:extrahead] || DEFAULT_CSS

    @last_time_check = Time.now
    @plainlogfile    = nil
    @htmllogfile     = nil
    @messagenum      = 0

    @filemutex = Mutex.new

    reopen_logs

    at_exit do
      @filemutex.synchronize do
        finish_html_file
        @htmllogfile.close
        @plainlogfile.close
      end
    end
  end

  def check_midnight
    time = Time.now

    # If day changed, finish this day’s logfiles and start new ones.
    reopen_logs unless @last_time_check.day == time.day

    @last_time_check = time
  end

  def log_public_message(msg)
    @filemutex.synchronize do
      log_plaintext_message(msg)
      log_html_message(msg)
    end
  end

  private

  def genfilename(ext)
    Time.now.strftime("%Y-%m-%d") + ext
  end

  def reopen_logs
    @filemutex.synchronize do
      # Close plain file if existing (startup!)
      @plainlogfile.close if @plainlogfile

      # Finish & Close HTML file if existing (startup!)
      if @htmllogfile
        finish_html_file
        @htmllogfile.close
      end

      # New files
      bot.info("Opening new logfiles.")
      @plainlogfile = File.open(File.join(@plainlogdir, genfilename(".log")), "a")
      @htmllogfile  = File.open(File.join(@htmllogdir, genfilename(".log.html")), "w") # Can't incrementally update HTML files

      # Log files should always be written directly to disk
      @plainlogfile.sync = true
      @htmllogfile.sync = true

      # Begin HTML log file
      @messagenum = 0
      start_html_file
    end
  end

  def log_plaintext_message(msg)
    @plainlogfile.puts(sprintf("%{time} %{nick} | %{msg}",
                               :time => msg.time.strftime(@timelogformat),
                               :nick => msg.user.name,
                               :msg => msg.message))
  end

  def log_html_message(msg)
    # Used for creating unique message IDs, see below
    @messagenum += 1

    str = <<-HTML
      <tr id="msg-#@messagenum">
        <td class="msgtime">#{msg.time.strftime(@timelogformat)}</td>
    HTML

    if msg.channel.opped?(msg.user)
      nickstatus = "opped"
    elsif msg.channel.half_opped?(msg.user)
      nickstatus = "halfopped"
    elsif msg.channel.voiced?(msg.user)
      nickstatus = "voiced"
    else
      nickstatus = ""
    end

    str << %Q!        <td class="msgnick #{nickstatus}">#{msg.user.name}</td>\n!
    str << %Q!        <td class="msgmessage">#{msg.message}</td>\n!
    str << %Q!        </tr>\n!

    @htmllogfile.write(str)
  end

  def start_html_file
    @htmllogfile.puts <<-HTML
<!DOCTYPE HTML>
<html>
  <head>
    <title>Chatlogs #{bot.config.channels.first} #{Time.now.strftime('%Y-%m-%d')}</title>
    <meta charset="utf-8"/>
#{@extrahead}
  </head>
  <body>
    <h1>Chatlogs for #{bot.config.channels.first}, #{Time.now.strftime('%Y-%m-%d')}</h1>
    <p>Nick colors:</p>
    <dl>
      <dt class="opped">Nick</dt><dd>Channel operator (+o)</dd>
      <dt class="halfopped">Nick</dt><dd>Channel half-operator (+h)</dd>
      <dt class="voiced">Nick</dt><dd>Nick is voiced (+v)</dd>
      <dt>Nick</dt><dd>Normal nick</dd>
    </dl>
    <hr/>
    <table class="chattable">
    HTML
  end

  def finish_html_file
    @htmllogfile.puts <<-HTML
    </table>
  </body>
</html>
    HTML
  end

end
