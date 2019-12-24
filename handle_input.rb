require 'pty'
require 'rspotify'


cmd = "jstest --event /dev/input/by-path/platform-3f980000.usb-usb-0\:1.4\:1.0-joystick"

# Event: type 1, time 1195000, number 0, value 1


tracks = {
        'beautiful': 'spotify:track:4KwsxBQhv0MVy4DgDWoOHz'
}

def play_track(track)
        puts("mpc stop && mpc clear && mpc add #{track} && sleep 0.1 && mpc play")
        fork { exec("mpc stop && mpc clear && mpc add #{track} && sleep 0.1 && mpc play") }
end

RSpotify.authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])

class State
        # mapping between physical connection and meaning
        buttons = {
                2 => :green_playlist,
                0 => :blue_playlist,
                1 => :yellow_playlist,
                3 => :red_playlist,
                5 => :volume_up,
                6 => :volume_down,
                4 => :play_pause
        }

        PLAYLISTS = {
                2 => 'green_playlist',
                0 => 'blue_playlist',
                1 => 'yellow_playlist',
                3 => 'red_playlist'
        }


        attr_accessor :playing, :current_playlist, :playlist_tracks

        def initialize
                @playing = false
                @current_playlist = nil
                @playlist_tracks = {}

                fetch_tracks
        end

        def handle_button_press(button)
                if [2, 0, 1, 3].include? button.to_i
                        playlist_button_pressed(PLAYLISTS[button.to_i])
                elsif [4].include? button.to_i
                        `mpc toggle`
                elsif [5].include? button.to_i
                        `mpc volume +10`
                elsif [6].include? button.to_i
                        `mpc volume -10`
                end
        end

        def playlist_button_pressed(playlist_name)
                puts "playlist name: #{playlist_name}"
                if (@current_playlist == playlist_name)
                        next_track
                else
                        @current_playlist = playlist_name
                        play_playlist
                end
        end

        def fetch_tracks
                puts "Fetching playlists"
                playlists = RSpotify::User.find('smittles2003').playlists


                playlists.each do |playlist|
                        if ['green_playlist', 'blue_playlist', 'yellow_playlist', 'red_playlist'].include?(playlist.name)
                                puts "#{playlist.name} has #{playlist.tracks.count} tracks"
                                @playlist_tracks[playlist.name] = playlist.tracks.map { |t| t.id}
                        end
                end
        end

        private

        def next_track
                queued = do_and_say('mpc queued')

                puts "queued: #{queued}"
                if (queued.delete(' ') != '')
                        do_and_say('mpc next')
                else
                        play_playlist
                end
        end

        def play_playlist
                pp @playlist_tracks
                pp @current_playlist


                do_and_say('mpc clear')
                (@playlist_tracks[@current_playlist] || []).each do |id|
                        do_and_say("mpc add spotify:track:#{id}")
                end
                do_and_say('mpc play')
        end

        def do_and_say(command)
                puts command
                `#{command}`
        end
end

state = State.new

held_buttons = []

begin
  debug = false
  PTY.spawn( cmd ) do |stdout, stdin, pid|
    should_parse = false
    begin
      # Do stuff with the output here. Just printing to show it works
      stdout.each do |line|
        if !should_parse && line.match('Testing')
          should_parse = true
          next
        end

        next unless should_parse

        event, time, number, value = line.split(", ")

        if (debug)
                puts line
                puts "event: #{event}"
                puts "time: #{time}"
                puts "number: #{number}"
                puts "value: #{value}"
        end

        number = number.split(" ")[1].delete(' ')
        value = value.split(" ")[1].delete(' ')

        puts "#{number}: #{value == '1' ? 'on' : 'off'}"

        button_up = value == '0'
        button_down = !button_up

        if (button_up)
                held_buttons -= [number]

                if (held_buttons == [])
                        state.handle_button_press(number)
                end
        else
                held_buttons << number
                puts "HELD BUTTONS: #{held_buttons}"
                if (held_buttons.sort == ['0', '1', '2', '3'])
                        state.fetch_tracks
                end
        end
      end
    rescue Errno::EIO
      puts "Errno:EIO error, but this probably just means " +
            "that the process has finished giving output"
    end
  end
rescue PTY::ChildExited
  puts "The child process exited!"
end