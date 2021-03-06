require 'progressbar'

module FlickrUploader
  class SetCreator
    include Configuration
    include RescueRetry

    def initialize(set_name)
      @set_name = set_name
      initialize_uploader
    end

    # Loop over all JPG files and upload them to a set.
    def upload_files(file_paths)
      logger.info "Starting upload of #{file_paths.size} photos to photoset '#{@set_name}'."
      @progressbar = progressbar(file_paths.size)

      file_paths.each do |file_path|
        filename = File.basename(file_path)
        logger.debug "Uploading: #{filename} .. "

        unless photo_uploaded?(filename)
          upload_file(file_path)
        else
          logger.info "Skipping '#{filename}', already uploaded! #(photo_id = #{photos_by_name(filename).map(&:id).join(' ')})"
        end
        @progressbar.inc
      end

      @progressbar.finish
      logger.info "Done uploading #{file_paths.size} photos to photoset '#{@set_name}'."
    end

    private

    def upload_file(file_path)
      # upload photo
      log_speed(File.size(file_path)) do
        rescue_retry(times: 20, sleep: 2.5) do
          result = @uploader.upload(file_path)

          photo_id = result.photoid.to_s
          logger.debug "Success! (photo_id = #{photo_id})"

          # add photo to set
          add_to_set(@set_name, photo_id)
        end
      end
    end

    def log_speed(size)
      start = Time.now.to_f
      yield
      finish = Time.now.to_f
      speed_kibs = ((size / (finish - start)) / 1024.0).round(1)
      @progressbar.speed = speed_kibs
      logger.debug "Speed: #{speed_kibs}KiB/s"
    end

    def initialize_uploader
      initialize_flickr
      @uploader = Flickr::Uploader.new(@flickr)

      # Find set, if it exists. This also triggers initial authentication.. (which is needed!)
      @set = find_set(@set_name)
    end

    def find_set(name)
      @photosets = Flickr::Photosets.new(@flickr)
      @photosets.get_list.find { |set| set.title == name }
    end

    def create_set(set_name, photo_id)
      logger.debug "Creating new set '#{set_name}'"
      @photosets.create(set_name, photo_id)
      find_set(set_name)
    end

    def add_to_set(set_name, photo_id)
      if !@set
        @set = create_set(set_name, photo_id)
      else
        logger.debug "Adding to existing set '#{set_name}'"
        @set.add_photo(photo_id)
      end
    end

    def photo_uploaded?(filename)
      return false unless @set
      photos_by_name(filename).any?
    end

    def photos_by_name(filename)
      return [] unless @set
      @photos ||= @set.get_photos
      base_filename = File.basename(filename, File.extname(filename))
      @photos.select { |photo| photo.title == base_filename }
    end

    def logger
      FlickrUploader.logger
    end

    def progressbar(size)
      progressbar = ProgressBar.new("Upload", size)
      progressbar.format_arguments = [:count, :percentage, :bar, :stat]
      progressbar.bar_mark = '='
      progressbar
    end

  end
end
