class InstancesCleanup < AwsCleanup
  def self.run
    InstancesCleanup.new.cleanup_instances
  end

  def cleanup_instances
    eii = expired_instances_ids
    if eii.any?
      prompt_user eii if eii.count > DELETE_LIMIT
      puts 'Deleting instances: ' + eii.join(', ')
      ec2.terminate_instances instance_ids: eii
      return
    end

    puts 'No instances to clean up'
  end

  private

  def prompt_user(eii)
    puts "WARNING: The following #{eii.count} instances will be terminated."
    print 'Are you sure? '
    return if %w(y ye yes).include? gets.strip
    puts 'Aborted'
    exit 1
  end

  def expired_instances_ids
    expired_instances.map(&:instance_id)
  end

  def expired_instances
    expired_test_instances | instances_expired_by_tag
  end

  def expired_test_instances
    test_instances.select { |instance| expired_age? TEST_INSTANCE_EXPIRE_AGE, instance.launch_time }
  end

  def test_instances
    instances.select do |instance|
      instance.security_groups.find do |sg|
        sg.group_name == TEST_GROUP_NAME || sg.group_id == TEST_GROUP_ID
      end ||
        instance.tags.find { |t| t.key == 'Type' && t.value == 'test' }
    end
  end

  def instances_expired_by_tag
    instances.select do |instance|
      instance.tags.find do |t|
        (t.key == 'expire_after' && expired_age?(t.value, instance.launch_time)) ||
          (t.key == 'expires' && expired_time?(t.value))
      end
    end
  end

  def expired_age?(secs, launch_time)
    Time.now > (launch_time + secs)
  end

  def expired_time?(timestamp)
    # `timestamp` should be a string in this format:
    # 2017-05-10 13:04:01 -0400
    Time.now > Time.parse(timestamp)
  end
end
