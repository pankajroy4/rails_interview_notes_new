oky, i am giving you code file by file.
1: This from where the job gets enqued: (Focus on parts_master case):
# app/workers/vwg_file_processor.rb


class VwgFileProcessor < ApplicationProcessor
  @queue = "volkswagen_edi_queue"
  LOGGER = Logger.new "log/volkswagen_file_processor_#{Date.today}.log"
  LOGGER.level = Logger::INFO

  def self.perform(options = {})
    self.new.select_db_for_queue_process(options['vw_context'])
    begin
      dup_options = options.with_indifferent_access
      case dup_options["file_type"].to_s&.downcase
      when "trade_dealer_rate"
        LOGGER.info "\n\n============== LabourRateFileProcessor PROCESS STARTED =================="
        LabourRateFileProcessor.process(dup_options)
      when "parts_master"
        LOGGER.info "\n\n============== PartsPriceUploadFileProcessor PROCESS STARTED =================="
        PartsPriceUploadFileProcessor.process(dup_options, LOGGER)
      when "discount_code"
        LOGGER.info "\n\n============== PartsDiscountCodeUploadFileProcessor PROCESS STARTED =================="
        PartsDiscountCodeUploadFileProcessor.process(dup_options)
      else
        raise "invalid file_type provided"
      end
    rescue => e
      LOGGER.info "Error"
      LOGGER.info e.message
      LOGGER.info e.backtrace
    end
  end
end

===============================
2:lib/parts_price_upload_file_processor.rb

# This class is to process the Parts price data
class PartsPriceUploadFileProcessor
  LINE_BYTESIZE = 606 #bytesize of a single line in the parts master file
  LINES_PER_CHUNK = 20000

  class << self
    # Processes a parts price upload file by dividing it into chunks and either processing directly
    # (info run) or enqueuing the chunks for background processing.
    #
    # @param options [Hash] Configuration options for file processing. Possible keys include:
    #   - 'info_run' [Boolean]: If true, processes the file synchronously for informational purposes.
    #   - 'file_name' [String]: The S3 file path (key) for the parts price upload file.
    #     Example: 'edi/vw/parts_data/PartsMasterFull-All-20241116181538.txt'
    #   - 'overwrite_existing_part' [Boolean]: If false, truncates the 'part_temporaries' collection
    #     to store new records.
    #   - 'vw_context' [Boolean]: Context flag for Volkswagen-specific processing logic.
    # @param logger [Logger, nil]: Optional logger instance for logging messages. If nil, a default 
    #   logger is created with a log file named 'volkswagen_file_processor_<current_date>.log'.
    #
    def process(options, logger = nil)
      @logger = logger || Logger.new("log/volkswagen_file_processor_#{Date.today}.log")
      start_time = Time.now
      @info_run_total_count = 0

      begin
        get_document(options)
        return @info_run_total_count
      rescue => e
        raise "PartsPriceUploadError:: Parts price upload initiated at #{start_time} failed at #{Time.now}.\n\nError:: #{e.message}\n\nBacktrace:: #{e.backtrace}"
      end
    end

    def get_document(options)
      begin
        if !options["overwrite_existing_part"] && !options[:info_run]
          # Mongoid.default_client[:part_temporaries].drop
          PartTemporary.collection.drop
          PartTemporary.create_indexes
          @logger.info "PART_TEMPORARY COLLECTION TRUNCATED TO STORE NEW RECORDS"
        end

        redis_url = get_redis_url
        redis = begin
          Redis.new(url: redis_url)
        rescue => e
          raise "Redis connection failed: #{e.message}"
        end

        options.merge!(redis_url: redis_url).with_indifferent_access
        file_key = options["file_name"]
        total_chunks_key = "chunks:#{file_key}:total"
        processed_chunks_key = "chunks:#{file_key}:processed"

        # Reset Redis counters
        redis.set(total_chunks_key, 0)
        redis.set(processed_chunks_key, 0)

        chunk_size = LINE_BYTESIZE * LINES_PER_CHUNK
        @chunk_no = 1
        @total_chunk = 0
        start_byte = 0
        process_started_date = Date.today

        remaining_line = +"".force_encoding('UTF-8') # Mutable string for leftover lines

        loop do
          puts "==================Fetching Chunk ##{@chunk_no}====================="
          end_byte = start_byte + chunk_size - 1

          # Fetch chunk data from S3
          s3_response = s3_client.get_object(
            bucket: S3Utilities.s3_config["docs_bucket"],
            key: options["file_name"],
            range: "bytes=#{start_byte}-#{end_byte}"
          )

          # Combine leftover line with current chunk
          chunk_data = remaining_line + s3_response.body.read.force_encoding('UTF-8')

          # Split lines and update remaining_line
          complete_lines, remaining_line = split_lines(chunk_data)

          @total_chunk += 1

          if options[:info_run]
            result = PartsPriceUploadFileChunkService.process(@chunk_no, complete_lines, nil, options)
            @info_run_total_count += result
          else
            Resque.enqueue(
              VwgPartsPriceUploadFileChunkProcessor,
              @chunk_no,
              complete_lines,
              process_started_date,
              options
            )
          end

          # Stop if the chunk size is smaller than expected (last chunk)
          break if s3_response.content_length < chunk_size

          start_byte += chunk_size
          @chunk_no += 1
        end

        # Process any remaining incomplete line
        unless remaining_line.empty?
          @total_chunk += 1

          if options[:info_run]
            result = PartsPriceUploadFileChunkService.process(@chunk_no, [remaining_line], nil, options)
            @info_run_total_count += result
          else
            Resque.enqueue(
              VwgPartsPriceUploadFileChunkProcessor,
              @chunk_no,
              [remaining_line],
              process_started_date,
              options
            )
          end
        end
        redis.set(total_chunks_key, @total_chunk)
        return if options[:info_run]
        @logger.info "TOTAL #{@total_chunk} CHUNKS FETCHED AND ENQUEUED #{@total_chunk} JOBS TO PROCESS"
      rescue => e
        @logger.info "Error occurred in PartsPriceUploadFileProcessor: #{e.message}\n, Backtrace: #{e.backtrace}"
        clean_failed_jobs
      end
    end

    def s3_client
      S3Utilities.open_s3_connection.client
    end

    # Utility method to split lines and handle incomplete lines
    def split_lines(chunk_data)
      # Use regex to split on line breaks (\r\n or \n) without consuming the last line if incomplete
      lines = chunk_data.scan(/.*?(?:\r\n|\n)|.+\z/)
      
      # Check if the last line ends with \r\n or \n; if not, treat it as incomplete
      if lines.last && !(lines.last.end_with?("\r\n", "\n"))
        remaining_line = lines.pop  # Remove and store the incomplete line
      else
        remaining_line = ""
      end
    
      [lines, remaining_line]
    end

    def clean_failed_jobs
      @logger.info "REMOVING THE ENQUEUED JOBS"

      # Remove Pending Jobs
      destroyed_jobs_count = Resque::Job.destroy("volkswagen_parts_queue", VwgPartsPriceUploadFileChunkProcessor)
      Resque.workers.each do |worker|
        if worker.job && worker.job['queue'] == 'volkswagen_parts_queue'
          if worker.job['payload']['class'] == 'VwgPartsPriceUploadFileChunkProcessor'
            worker.done_working # Mark the job as failed or processed to remove it
            destroyed_jobs_count += 1
          end
        end
      end

      @logger.info "#{destroyed_jobs_count} ENQUEUED JOBS REMOVED"
    end

    def get_redis_url
      begin
        resque_config = YAML.load(ERB.new(File.read('config/resque.yml')).result)

        unless resque_config[Rails.env]
          raise "Missing Redis URL for environment: #{Rails.env}"
        end

        url = resque_config[Rails.env]
        "redis://#{url}"
      rescue Errno::ENOENT => e
        raise "Redis configuration file 'config/resque.yml' not found: #{e.message}"
      rescue Psych::SyntaxError => e
        raise "Error while parsing Redis configuration 'config/resque.yml' file: #{e.message}"
      rescue => e
        raise "An error occurred while fetching the Redis URL: #{e.message}"
      end
    end
  end
end

===============================================
3:lib/parts_price_upload_file_chunk_service.rb

class PartsPriceUploadFileChunkService
  PART_PROCESSING_TEMP_FOLDER_PATH = "#{Rails.root}/tmp/part_processing"

  class << self
    def process(chunk_no, chunk_lines, logger, options)
      begin
        @logger = logger
        @logger.info "STARTED PROCESSING CHUNK: #{chunk_no}" if !options[:info_run]
        redis = begin
          Redis.new(url: options[:redis_url])
        rescue => e
          raise "Redis connection failed: #{e.message}"
        end
        file_key = options["file_name"]
        processed_chunks_key = "chunks:#{file_key}:processed"
        total_chunks_key = "chunks:#{file_key}:total"

        parts_info = initialize_parts_info
        company = Company.find_by(slug: "volkswagen_group_uk_ltd_de_fleet")

        @info_run_total_count = 0
        @total_line_count = 0
        @total_line_strat_with_M = 0
        @total_line_with_suppression_type_M_or_O = 0
        @total_line_with_unsupported_encoding = 0
        @chunk_no = chunk_no
        @invalid_lines = []

        parts = []

        chunk_lines.each do |line|
          if line.size < PartsPriceUploadFileProcessor::LINE_BYTESIZE - 2
            @invalid_lines << line
          end

          @total_line_count += 1
          next unless line.start_with?("M")
          @total_line_strat_with_M += 1

          supression_type = line[191, 1]
          if ["O", "M"].include?(supression_type)
            @total_line_with_suppression_type_M_or_O += 1
            next
          end

          if options["info_run"]
            @info_run_total_count += 1
            next
          end

          begin
            part = parse_line_and_create_part_in_temporary_collection(line, parts_info, company, options)
            if part.present?
              card_part_number = part.card_part_number
              parts_info[:processed_card_part_numbers] << {
                card_part_number: card_part_number,
                description: part.material_short_text_selection_screen,
              }

              parts << {
                replace_one: {
                  filter: { card_part_number: card_part_number },
                  replacement: part.attributes.except('_id'),
                  upsert: true
                }
              }
            end
          rescue Encoding::UndefinedConversionError => e
            @total_line_with_unsupported_encoding += 1
            @logger.info "[#{@chunk_no}], SKIPPING LINE DUE TO UNSUPPORTED ENCODING: #{line.encoding.name}, MESSAGE: #{e.message}" if !options[:info_run]
          rescue => e
            @logger.error "[#{@chunk_no}], ERROR WHILE PROCESSING THE LINE: #{e.message}, LINE: #{line}" if !options[:info_run]
          end
        end

        return @info_run_total_count if options[:info_run]

        if options['overwrite_existing_part']
          Part.collection.bulk_write(parts)
        else
          PartTemporary.collection.bulk_write(parts)
        end

        store_parts_info(parts_info)
        @logger.info "COMPLETED PROCESSING CHUNK: #{chunk_no}"

        redis.incr(processed_chunks_key)
        total_chunks = redis.get(total_chunks_key).to_i
        processed_chunks = redis.get(processed_chunks_key).to_i

        if processed_chunks == total_chunks
          formated_part_info = get_formatted_parts_info(options['overwrite_existing_part'])

          @logger.info "ALL CHUNKS PROCESSED SUCCESSFULLY"          
          @logger.info "TOTAL LINES PRESENT IN THE FILE: #{formated_part_info['total_line_count']}"
          @logger.info "TOTAL LINES SKIPPED DUE TO UNSUPPORTED ENCODING: #{formated_part_info['total_line_with_unsupported_encoding']}"
          @logger.info "TOTAL LINES PROCESSED START WITH M: #{formated_part_info['total_line_strat_with_M']}"
          @logger.info "TOTAL LINES START WITH M BUT SKIPPED DUE TO SUPPRESSION TYPE M OR O: #{formated_part_info['total_line_with_suppression_type_M_or_O']}\n"

          if !options['overwrite_existing_part']
            @logger.info "TOTAL RECORDS CREATED SUCCESSFULLY IN THE PartTemporary COLLECTION: #{PartTemporary.count}"
            @logger.info "NOTE: TAKE DUMP OF THE PartTemporary COLLECTION AND RESTORE DUMP DATA INTO Part COLLECTION MANULLY"
          end

          send_notification(formated_part_info)
          redis.set(total_chunks_key, 0)
          redis.set(processed_chunks_key, 0)

          @logger.info "Processed File Summary"
          @logger.info "\t - Total Lines in File: #{formated_part_info['total_line_count']}"
          @logger.info "\t - Lines Starting with 'M': #{formated_part_info['total_line_strat_with_M']} (Only these lines are processed)"
          @logger.info "\t - Skipped Lines (Suppression Type 'M' or 'O'): #{formated_part_info['total_line_with_suppression_type_M_or_O']}"
          @logger.info "\t - Lines with Unsupported Encoding: #{formated_part_info['total_line_with_unsupported_encoding']}"
          @logger.info "\t - Validation Failures During Processing: #{formated_part_info['invalid_material_numbers_count']}"
          @logger.info "\t - Valid Parts Processed: #{formated_part_info['valid_parts_count']}\n\n"

          @logger.info "Verification of Valid Parts Count:"
          @logger.info "\tValid Parts Processed = Lines Starting with 'M' - (Skipped Lines + Lines with Unsupported Encoding + Validation Failures)"
          @logger.info "\t= #{formated_part_info['total_line_strat_with_M']} - (#{formated_part_info['total_line_with_suppression_type_M_or_O']} + #{formated_part_info['total_line_with_unsupported_encoding']} + #{formated_part_info['invalid_material_numbers_count']})"
          @logger.info "\t= #{formated_part_info['total_line_strat_with_M']  - (formated_part_info['total_line_with_suppression_type_M_or_O'] + formated_part_info['total_line_with_unsupported_encoding'] + formated_part_info['invalid_material_numbers_count']) }"
          redis.del(processed_chunks_key)
          redis.del(total_chunks_key)
        end
      rescue => e
        @logger.info "[#{@chunk_no}], ERROR WHILE PROCESSING THE CHUNK: #{e.message} \n #{e.backtrace}"
      end
    end

    def initialize_parts_info
      {
        valid_parts_count: 0,
        invalid_material_numbers_count: 0,
        invalid_material_numbers_and_errors: [],
        processed_card_part_numbers: [],
      }
    end

    def store_parts_info(parts_info)
      FileUtils.mkdir_p(PART_PROCESSING_TEMP_FOLDER_PATH) unless Dir.exist?(PART_PROCESSING_TEMP_FOLDER_PATH)

      filepath = "#{Rails.root}/tmp/part_processing/#{@chunk_no}.json"
      parts_info[:chunk_no] = @chunk_no

      parts_info[:total_line_count] = @total_line_count
      parts_info[:total_line_strat_with_M] = @total_line_strat_with_M
      parts_info[:total_line_with_suppression_type_M_or_O] = @total_line_with_suppression_type_M_or_O
      parts_info[:total_line_with_unsupported_encoding] = @total_line_with_unsupported_encoding
      parts_info[:invalid_lines] = @invalid_lines

      File.open(filepath, "w") do |file|
        file.write(JSON.pretty_generate(parts_info))
      end
    end

    def send_notification(parts_info)
      begin
        send_notification_to_uploader(parts_info.with_indifferent_access)
        @logger.info "PART PRICE UPLAODED EMAIL SENT SUCCESSIFULLY\n\n"
      rescue => e
        @logger.info "ERROR WHILE SENDING EMAIL FOR PARTS PRICE UPLOAD: #{e.message}\n\n"
      end
    end

    def get_formatted_parts_info(overwrite_existing_part)
      summary_file_path = "#{Rails.root}/tmp/chunk_parts_summary_info.json"
      part_counts = Hash.new(0)  # Hash to track occurrences of card_part_numbers
      duplicate_card_part_numbers = []  # List to store duplicates as they appear
      accumulated_result = {}

      Dir.glob("#{PART_PROCESSING_TEMP_FOLDER_PATH}/*.json").each do |filepath|
        File.open(filepath, "r") do |file|
          json_data = JSON.parse(file.read)

          # Process card part numbers efficiently
          unless overwrite_existing_part
            if json_data["processed_card_part_numbers"]
              json_data["processed_card_part_numbers"].each do |part_info|
                card_part_number = part_info["card_part_number"]
                description = part_info["description"]

                part_counts[card_part_number] += 1

                # Add to the duplicates list if the card_part_number is a duplicate
                if part_counts[card_part_number] > 1
                  duplicate_card_part_numbers << { card_part_number: card_part_number, description: description }
                end
              end
            end
          end

          # Accumulate other numeric and array values
          json_data.each do |key, value|
            next if key == "chunk_no" || key == "processed_card_part_numbers"
            case value
            when Array
              # Initialize the array if the key is not already present
              accumulated_result[key] ||= []
              accumulated_result[key].concat(value)
            when Numeric
              # Initialize the numeric value if the key is not already present
              accumulated_result[key] ||= 0
              accumulated_result[key] += value
            end
          end
        end
      end

      # Add duplicate info to the accumulated result
      accumulated_result["invalid_material_numbers_count"] = accumulated_result["invalid_material_numbers_count"].to_i + duplicate_card_part_numbers.size

      accumulated_result["invalid_material_numbers_and_errors"].concat(duplicate_card_part_numbers.map do |info|
        {
          ET2000_part_no: info[:card_part_number],
          description_english: info[:description],
          error_message: "card_part_number '#{info[:card_part_number]}' has already been taken.",
          line: ""
        }
      end)

      accumulated_result["invalid_material_numbers_and_errors"]
      accumulated_result["valid_parts_count"] = accumulated_result["valid_parts_count"].to_i - duplicate_card_part_numbers.size

      # Write summary to file
      File.write(summary_file_path, JSON.pretty_generate({ "summary" => accumulated_result }))

      # Cleanup directory
      FileUtils.rm_rf(PART_PROCESSING_TEMP_FOLDER_PATH) if Dir.exist?(PART_PROCESSING_TEMP_FOLDER_PATH)

      accumulated_result
    end

    def parse_line_and_create_part_in_temporary_collection(line, parts_info, company, options)
      cleaned_line = line.gsub(/[^\x00-\x7F]/, " ") # Clean line to replace non-ASCII characters with a space
      part_attributes = parse_line_and_map_with_part_attributes(cleaned_line)
      return nil if part_attributes.blank?
      create_new_part_in_temporary_collection(part_attributes, parts_info, company, options, cleaned_line)
    end

    def parse_line_and_map_with_part_attributes(line)
      begin
        fields = line.unpack("x7A18A8A8x40A40A2x64A3x2A18x2A2x5A18x293A15x1A15x23A1")
        # How it works:
        # This avoids creating multiple substrings.
        # unpack interprets the string based on a template:
        # A7 extracts the first 7 characters.
        # A18 extracts the next 18 characters.
        # x skips a specified number of characters.
        {
          material_number: fields[0]&.strip,                                      #ET2000_part_no
          card_part_number: fields[0]&.strip,                                     #ET2000_part_no
          recommended_retail_price_effective_date: parse_date(fields[1]),         #creation_date
          last_updated: parse_datetime(fields[2]),                                #date_last_changed
          material_short_text_selection_screen: fields[3]&.strip,                 #description_english
          division: fields[4]&.to_i,                                              #division_SPARTE
          dangerous_goods_indicator: fields[5]&.strip,                            #dangerous_goods_indicator
          follow_up_material: fields[6]&.strip,                                   #follow_up_material
          discount_code: fields[7]&.strip,                                        #pricing_group_1
          hpg_code: fields[8]&.strip,                                             #hpg
          product_hierarchy: fields[8]&.strip,                                    #hpg
          recommended_retail_price: fields[9]&.strip,                            #retail_price
          surcharge_value: fields[10]&.to_i,                                      #retail_price_v_part
          tax_code: fields[11],                                             #vat_code
        }
      rescue ArgumentError => e
        {
          material_number: line[7, 18]&.strip,
          card_part_number: line[7, 18]&.strip,
          recommended_retail_price_effective_date: parse_date(line[25, 8]),
          last_updated: parse_datetime(line[33, 8]),
          material_short_text_selection_screen: line[81, 40]&.strip,
          division: line[121, 2]&.to_i,
          dangerous_goods_indicator: line[187, 3]&.strip,
          follow_up_material: line[192, 18]&.strip,
          discount_code: line[212, 2]&.strip,
          hpg_code: line[219, 18]&.strip,
          product_hierarchy: line[219, 18]&.strip,
          recommended_retail_price: line[530, 15]&.strip,
          surcharge_value: line[546, 15]&.to_i,
          tax_code: line[584, 1],
        }
      rescue => e
        error_dir = "#{Rails.root}/tmp/part_price_errros/#{Date.today}"
        FileUtils.mkdir_p(error_dir) unless Dir.exist?(error_dir)
        file_path = "#{error_dir}/error.json"

        @logger.info "FAILED UNHANDELED CHUNKS AND LINES ARE REPORTED IN FILE: #{file_path} \n"
        data = {
          chunk_data: [
            {
              chunk_no: @chunk_no,
              line: line,
              error: e.message,
            }
          ]
        }

        # Check if the file exists and has valid JSON
        if File.exist?(file_path) && !File.zero?(file_path)
          existing_data = JSON.parse(File.read(file_path)) # Read and parse the current content
          existing_data["chunk_data"] ||= [] # Ensure "errors" key exists
          existing_data["chunk_data"] << data # Append new data to the "errors" array
        else
          existing_data = data
        end

        File.open(file_path, 'w') do |file|
          file.write(JSON.pretty_generate(existing_data))
        end

        return {}
      end
    end

    def parse_date(value)
      Date.parse(value) rescue nil
    end

    def parse_datetime(value)
      DateTime.parse(value) rescue nil
    end

    def create_new_part_in_temporary_collection(part_attributes, parts_info, company, options, line)
      if options['overwrite_existing_part']
        part = Part.new(company_id: company.id)
      else
        part = PartTemporary.new(company_id: company.id)
      end

      validate_and_convert_recommended_retail_price_to_money_object(part_attributes, part)
      validate_tax_code_numericality(part_attributes, part)
      validate_card_part_number_presence(part_attributes, part)
      part.assign_attributes(part_attributes)

      if part.errors.blank?
        parts_info[:valid_parts_count] += 1
        return part
      else
        parts_info[:invalid_material_numbers_and_errors].push({
          ET2000_part_no: part_attributes[:material_number],
          description_english: part_attributes[:material_short_text_selection_screen],
          error_message: part.errors.full_messages.join(", "),
          line: line
        })
        parts_info[:invalid_material_numbers_count] +=1
        return nil
      end
    end

    def validate_and_convert_recommended_retail_price_to_money_object(part_attributes, part)
      if part_attributes[:recommended_retail_price].present?
        if numeric_or_float?(part_attributes[:recommended_retail_price])
          price = part_attributes[:recommended_retail_price]&.to_f
          part_attributes[:recommended_retail_price] = Money.new(price * 100, "GBP")
        else
          part.errors.add(:base, "Retail price should be numeric or float value!")
        end
      else
        part_attributes[:recommended_retail_price] = Money.new(0, "GBP")
      end
    end

    def validate_tax_code_numericality(part_attributes, part)
      if part_attributes[:tax_code].present?
        if integer?(part_attributes[:tax_code])
          part_attributes[:tax_code] = part_attributes[:tax_code].to_i
        else
          part.errors.add(:base, "Tax code should be numeric!")
        end
      end
    end

    def validate_card_part_number_presence(part_attributes, part)
      unless part_attributes[:card_part_number].present?
        part.errors.add(:base, "Card part number must be present")
      end
    end

    def numeric_or_float?(string)
      true if Float(string) rescue false
    end

    def integer?(string)
      true if Integer(string) rescue false
    end

    def send_notification_to_uploader(parts_info)
      filepath = if (parts_info[:invalid_material_numbers_and_errors].count > 0)
        generate_error_report_csv(parts_info[:invalid_material_numbers_and_errors])
      end

      notification_options = {
        valid_parts_count: parts_info[:valid_parts_count],
        invalid_material_numbers_and_errors: parts_info[:invalid_material_numbers_and_errors],
        invalid_report_file_path: filepath
      }
      UserMailer.parts_price_processed_notification(Account.current.vw_context, notification_options).deliver
    end

    def generate_error_report_csv(data)
      csv_content = CSV.generate(headers: true) do |csv|
        csv << get_capitalized_headers(data.first.keys)
        data.each { |row| csv << row.values }
      end

      filepath = "#{Rails.root}/tmp/invalid_parts_report.csv"
      File.write(filepath, csv_content)
      filepath
    end

    def get_capitalized_headers(headers)
      headers.map { |e| e.to_s.split('_').map(&:capitalize).join('') }
    end
  end
end


========================================
As you can see all the files  that how i hanldes this optimization at scale, i did everthing like prepare a error report file too, sending emails too ad holding the data in part temporar model excetra.


So now you turn.
Prepare a fullly explainable ansewer to represent this work in intrview.