class CloudWatchCleanup < AwsCleanup
  def self.run
    CloudWatchCleanup.new.cleaup_alarms
  end

  def cleaup_alarms
    oa = orphaned_alarms.map(&:alarm_name)

    if oa.any?
      puts 'Deleting alarms: ' + oa.join(', ')
      cloudwatch.delete_alarms alarm_names: oa
      return
    end

    puts 'No alarms to clean up'
  end

  def orphaned_alarms
    insufficient_data_alarms.select do |alarm|
      alarm.dimensions.any? &&
        !alarm.dimensions.find { |dimension| dimension_in_use? dimension }
    end
  end

  def dimension_in_use?(dimension)
    case dimension.name
    when 'InstanceId'
      instance_ids.include? dimension.value
    when 'QueueName'
      queue_names.include? dimension.value
    when 'DBInstanceIdentifier'
      db_names.include? dimension.value
    else
      puts "Unsupported dimension: #{dimension.name}"
      true
    end
  end

  def db_names
    @db_names ||= rds.describe_db_instances.db_instances.map(&:db_instance_identifier)
  end

  def queue_names
    @queue_names ||= sqs.list_queues.queue_urls.map { |q| URI(q).path.split('/')[2..-1].join('/') }
  end

  def insufficient_data_alarms
    cloudwatch.describe_alarms(state_value: 'INSUFFICIENT_DATA').metric_alarms
  end

  def cloudwatch
    @cloudwatch ||= Aws::CloudWatch::Client.new
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new
  end

  def rds
    @rds ||= Aws::RDS::Client.new
  end
end
