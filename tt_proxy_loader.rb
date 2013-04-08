#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

# Ensure the TT::Plugins namespace exists - as this is where my plugins are
# located.
module TT; end;
module TT::Plugins; end;

# @note Requires TT_Lib2. See comments further down in the source on how to
#       remove its dependancy.
module TT::Plugins::ProxyLoader
  
  VERSION = '0.7.1'.freeze # Beta
  
  # Time the loading.
  time_start = Time.now
  
  # Locations where plugins are stored. Each location has a set of folders.
  # Each solder contains a plugin which will be added to the load path and
  # also loaded.
  user_folder = File.expand_path( ENV['USERPROFILE'] || ENV['HOME'] )
  base_folder = File.join( user_folder, 'Dropbox', 'SketchUp', 'Plugins' )
  locations = [
    File.join( base_folder, 'ThomThom', 'sketchup-developer-tools' ),
    File.join( base_folder, 'ThomThom', 'sketchup-stl' ),
    File.join( base_folder, 'Shared' ),
    File.join( base_folder, 'ThomThom' )
  ]
  
  # Containing all folders found at all locations in the pre-pass.
  paths = []
  
  # Pre-pass adding the folders to the load path. This is done in case one
  # plugin requires another. Such as a plugin require a library. With the
  # folders added to the load path the order which the folders are processes
  # won't matter.
  for location in locations
    Dir.chdir( location ) {
      # Find all sub-folders
      for folder in Dir.new( location )
        # Skip the special . and .. folders. The length is tested first in 
        # order to reduce the number of string comparisons. Hopefully this
        # will generally be faster - not tested. Might be unnessesary.
        next if folder.size <= 2 && ( folder == '.' || folder == '..' )
        # Ensure the item really is a folder/directory.
        path = File.join( location, folder )
        next unless FileTest.directory?( path )
        # Add the path to the load path so it's content can be loaded by
        # relative path as if it was located in the original plugins folder.
        unless $LOAD_PATH.include?( path )
          $LOAD_PATH << path
          paths << path
        end
      end # Dir.new
    } # chdir
  end # locations
  
  # Load TT_Lib2
  # (i) This assumes that TT_Lib2 is located in one of the locations in the
  #     $LOAD_PATH. It's requirement is entirely for debuggin purposes.
  #
  #     To remove it's dependancy, comment out the references to TT.debug and
  #     TT.defer.
  tt_lib_time = Time.now
  require 'TT_Lib2/core.rb'
  @tt_lib_load_time = Time.now - tt_lib_time
  
  # Debug wrapper
  def self.debug( string )
    TT.debug( string )
    puts string
  end
  
  puts "\nProxy Loader"
  puts "> Loading #{paths.size} plugins from #{locations.size} locations..."
  
  # Load the plugins found in the root of each folder.
  @files_load_times = []
  @load_times = []
  errors = ''
  for path in paths
    # Record the time it takes to load the files in this folder.
    path_start_time = Time.now
    # Load files...
    for file in Dir.glob( File.join( path, '*.{rb,rbs}' ) )
      begin
        # (?) Is SketchUp::require needed to load .rbs files?
        file_time = Time.now
        Sketchup::require( file )
        @files_load_times << [ file, Time.now - file_time ]
      rescue ScriptError => e
        # This catches LoadError, NotImplementedError and SyntaxError.
        filename = File.basename( file )
        error = ''
        error << "=== ScriptError ===\n"
        error << "File: #{filename}\n"
        error << "Path: #{path}\n"
        error << "--- Error Message ---\n"
        error << "#{e.message}\n"
        error << "#{e.backtrace.join("\n")}\n\n"
        # Error is outputted to the console and to the system debug. This is
        # to avoid modal messageboxes that interfer with the further loading
        # of the remaining plugins which might cause odd gremlings when loading.
        # 
        # Additionally it avoids the user from having to click on each error.
        #
        # The error messages is defered until the end when everything is loaded.
        self.debug( error )
        errors << error
      end
    end # Dir.glob
    # Add the load time.
    path_load_time = Time.now - path_start_time
    @load_times << {
      :path => path,
      :load_time => path_load_time
    }
  end # paths
  
  # TT::Plugins::ProxyLoader.total_load_time
  @time_total = Time.now - time_start
  def self.total_load_time; @time_total; end
  
  puts "\nProxy Loader"
  puts "> Done! #{@time_total}s"
  
  # Log performance data.
  section = 'TT_ProxyLoader\Profiler'
  for stat in @load_times
    path = stat[:path]
    load_time = stat[:load_time]
    # Prepare keys
    section = "TT_ProxyLoader\\Profiler\\#{path}"
    # Read previous data.
    logged_time = Sketchup.read_default( section, 'LoadTime', 0.0 )
    logged_load_count = Sketchup.read_default( section, 'LoadCount', 0 )
    # Calculate new data.
    new_count = logged_load_count + 1
    new_time = logged_time + load_time
    # Write back data.
    Sketchup.write_default( section, 'LoadTime', new_time )
    Sketchup.write_default( section, 'LoadCount', new_count )
    Sketchup.write_default( section, 'LastRun', Time.now )
  end
  
  # Accessor for load times statistics
  # TT::Plugins::ProxyLoader.load_times
  def self.load_times; @load_times.dup; end
  
  # Accessor for current session file load times statistics
  # TT::Plugins::ProxyLoader.files_load_times
  def self.files_load_times; @files_load_times.dup; end
  
  # Outputs formatted stats.
  # TT::Plugins::ProxyLoader.print_load_times
  def self.print_load_times
    sub_total = 0
    string = "\nProxy Loader - Loading Statistics\n\n"
    for stat in @load_times
      str_load_time = sprintf( '%.3f', stat[:load_time] )
      string << "Path: #{stat[:path]}\n"
      string << "        Load Time: #{str_load_time}s\n"
      # Load stats
      section = "TT_ProxyLoader\\Profiler\\#{stat[:path]}"
      load_count = Sketchup.read_default( section, 'LoadCount' )
      if load_count
        load_time = Sketchup.read_default( section, 'LoadTime', 0.0 )
        average = load_time / load_count
        str_average = sprintf( '%.3f', average )
        string << "Average Load Time: #{str_average}s (#{load_count} times)\n"
      end
      string << "\n"
      sub_total += stat[:load_time]
    end
    string << "-----\nSubTotal: #{sub_total}s\n"
    string << "-----\nTotal: #{@time_total}s\n====="
    # Special case for TT_Lib2 as it's preloaded
    string << "\nTT_Lib2: #{@tt_lib_load_time}s\n====="
    puts string
  end
  
  # Display any loading errors.
  unless errors.empty?
    # Defer the action so it doesn't block the loading of other plugins that's
    # loaded after this proxy loader.
    TT.defer {
      UI.messagebox( errors, MB_MULTILINE )
    }
  end
  
end # module TT::Plugins::ProxyLoader