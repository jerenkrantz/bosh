require 'spec_helper'

describe 'run errand', type: :integration, with_tmp_dir: true do
  context 'while errand is running' do
    with_reset_sandbox_before_each

    let(:manifest_hash) do
      manifest_hash = Bosh::Spec::Deployments.manifest_with_errand
      manifest_hash['properties'] = {
        'errand1' => {
          'sleep_duration_in_seconds' => 60,
        },
      }
      manifest_hash
    end

    it 'creates a deployment lock' do
      deploy_simple(manifest_hash: manifest_hash)

      bosh_runner.run('--no-track run errand fake-errand-name')
      output = bosh_runner.run_until_succeeds('locks')
      expect(output).to match(/\s*\|\s*deployment\s*\|\s*errand\s*\|/)
    end
  end

  context 'when multiple errands exist in the deployment manifest' do
    with_reset_sandbox_before_each

    let(:manifest_hash) do
      manifest_hash = Bosh::Spec::Deployments.simple_manifest

      # Include other jobs in the deployment
      manifest_hash['resource_pools'].first['size'] = 3
      manifest_hash['jobs'].first['instances'] = 1

      # First errand
      manifest_hash['jobs'] << {
        'name'          => 'errand1-name',
        'template'      => 'errand1',
        'lifecycle'     => 'errand',
        'resource_pool' => 'a',
        'instances'     => 1,
        'networks'      => [{ 'name' => 'a' }],
        'properties' => {
          'errand1' => {
            'exit_code' => 0,
            'stdout'    => 'some-errand1-stdout',
            'stderr'    => 'some-errand1-stderr',
            'run_package_file' => true,
          },
        },
      }

      # Second errand
      manifest_hash['jobs'] << {
        'name'          => 'errand2-name',
        'template'      => 'errand1',
        'lifecycle'     => 'errand',
        'resource_pool' => 'a',
        'instances'     => 2,
        'networks'      => [{ 'name' => 'a' }],
        'properties' => {
          'errand1' => {
            'exit_code' => 0,
            'stdout'    => 'some-errand2-stdout',
            'stderr'    => 'some-errand2-stderr',
            'run_package_file' => true,
          },
        },
      }

      manifest_hash
    end

    context 'with a fixed size resource pool size' do
      before { manifest_hash['resource_pools'].first['size'] = 3 }

      it 'allocates enough empty VMs for the largest errand on deploy and reallocates empty VMs after each errand run' do
        deploy_simple(manifest_hash: manifest_hash)
        expect_running_vms(%w(foobar/0 unknown/unknown unknown/unknown))

        output, exit_code = bosh_runner.run('run errand errand1-name', return_exit_code: true)
        expect(output).to include('some-errand1-stdout')
        expect(exit_code).to eq(0)
        expect_running_vms(%w(foobar/0 unknown/unknown unknown/unknown))

        output, exit_code = bosh_runner.run('run errand errand2-name', return_exit_code: true)
        expect(output).to include('some-errand2-stdout')
        expect(exit_code).to eq(0)
        expect_running_vms(%w(foobar/0 unknown/unknown unknown/unknown))
      end
    end

    context 'with a dynamically sized resource pool size' do
      before { manifest_hash['resource_pools'].first.delete('size') }

      it 'allocates and deallocates errand vms for each errand run' do
        deploy_simple(manifest_hash: manifest_hash)
        expect_running_vms(%w(foobar/0))

        output, exit_code = bosh_runner.run('run errand errand1-name', return_exit_code: true)
        expect(output).to include('some-errand1-stdout')
        expect(exit_code).to eq(0)
        expect_running_vms(%w(foobar/0))

        output, exit_code = bosh_runner.run('run errand errand2-name', return_exit_code: true)
        expect(output).to include('some-errand2-stdout')
        expect(exit_code).to eq(0)
        expect_running_vms(%w(foobar/0))
      end
    end
  end

  context 'when errand script exits with 0 exit code' do
    with_reset_sandbox_before_all
    with_tmp_dir_before_all

    before(:all) do
      manifest_hash = Bosh::Spec::Deployments.simple_manifest

      # Include other jobs in the deployment
      manifest_hash['jobs'].first['instances'] = 1

      # Currently errands are represented via jobs
      manifest_hash['jobs'] << {
        'name'          => 'errand1-name',
        'template'      => 'errand1',
        'lifecycle'     => 'errand',
        'resource_pool' => 'a',
        'instances'     => 1,
        'networks'      => [{ 'name' => 'a' }],
        'properties' => {
          'errand1' => {
            'exit_code' => 0,
            'stdout'    => 'some-stdout',
            'stderr'    => 'some-stderr',
            'run_package_file' => true,
          },
        },
      }

      deploy_simple(manifest_hash: manifest_hash)

      @output, @exit_code = bosh_runner.run("run errand errand1-name --download-logs --logs-dir #{@tmp_dir}",
                                            {return_exit_code: true})
    end

    it 'shows bin/run stdout and stderr' do
      expect(@output).to include('some-stdout')
      expect(@output).to include('some-stderr')
    end

    it 'shows output generated by package script which proves dependent packages are included' do
      expect(@output).to include('stdout-from-errand1-package')
    end

    it 'downloads errand logs and shows downloaded location' do
      expect(@output =~ /Logs saved in `(.*errand1-name\.0\..*\.tgz)'/).to_not(be_nil, @output)
      logs_file = Bosh::Spec::TarFileInspector.new($1)
      expect(logs_file.file_names).to match_array(%w(./errand1/stdout.log ./custom.log))
      expect(logs_file.smallest_file_size).to be > 0
    end

    it 'returns 0 as exit code from the cli and indicates that errand ran successfully' do
      expect(@output).to include('Errand `errand1-name\' completed successfully (exit code 0)')
      expect(@exit_code).to eq(0)
    end
  end

  context 'when errand script exits with non-0 exit code' do
    with_reset_sandbox_before_all
    with_tmp_dir_before_all

    before(:all) do
      manifest_hash = Bosh::Spec::Deployments.simple_manifest

      # Include other jobs in the deployment
      manifest_hash['jobs'].first['instances'] = 1

      # Currently errands are represented via jobs
      manifest_hash['jobs'] << {
        'name'          => 'errand1-name',
        'template'      => 'errand1',
        'lifecycle'     => 'errand',
        'resource_pool' => 'a',
        'instances'     => 1,
        'networks'      => [{ 'name' => 'a' }],
        'properties' => {
          'errand1' => {
            'exit_code' => 23, # non-0 (and non-1) exit code
            'stdout'    => '', # No output
            'stderr'    => "some-stderr1\nsome-stderr2\nsome-stderr3",
          },
        },
      }

      deploy_simple(manifest_hash: manifest_hash)

      @output, @exit_code = bosh_runner.run("run errand errand1-name --download-logs --logs-dir #{@tmp_dir}",
                                            {failure_expected: true, return_exit_code: true})
    end

    it 'shows errand\'s stdout and stderr' do
      expect(@output).to include("[stdout]\nNone")
      expect(@output).to include("some-stderr1\nsome-stderr2\nsome-stderr3")
    end

    it 'downloads errand logs and shows downloaded location' do
      expect(@output =~ /Logs saved in `(.*errand1-name\.0\..*\.tgz)'/).to_not(be_nil, @output)
      logs_file = Bosh::Spec::TarFileInspector.new($1)
      expect(logs_file.file_names).to match_array(%w(./errand1/stdout.log ./custom.log))
      expect(logs_file.smallest_file_size).to be > 0
    end

    it 'returns 1 as exit code from the cli and indicates that errand completed with error' do
      expect(@output).to include('Errand `errand1-name\' completed with error (exit code 23)')
      expect(@exit_code).to eq(1)
    end
  end

  context 'when errand is canceled' do
    with_reset_sandbox_before_each

    let(:manifest_hash) do
      manifest_hash = Bosh::Spec::Deployments.manifest_with_errand

      # Sleep so we have time to cancel it
      manifest_hash['jobs'].last['properties']['errand1']['sleep_duration_in_seconds'] = 5000

      manifest_hash
    end

    it 'successfully cancels the errand and returns exit code' do
      deploy_simple(manifest_hash: manifest_hash)

      errand_result = bosh_runner.run('--no-track run errand fake-errand-name')
      task_id = Bosh::Spec::OutputParser.new(errand_result).task_id('running')

      director.wait_for_vm('fake-errand-name/0', 10)

      cancel_output = bosh_runner.run("cancel task #{task_id}")
      expect(cancel_output).to match(/Task #{task_id} is getting canceled/)

      errand_output = bosh_runner.run("task #{task_id}")
      expect(errand_output).to include("Error 10001: Task #{task_id} cancelled")

      # Cannot assert on output because there is no guarantee
      # that process will be cancelled after output is echoed
      result_output = bosh_runner.run("task #{task_id} --result")
      expect(result_output).to include('"exit_code":143')
    end
  end

  context 'when errand cannot be run because there is no bin/run found in the job template' do
    with_reset_sandbox_before_each

    let(:manifest_hash) do
      manifest_hash = Bosh::Spec::Deployments.simple_manifest

      # Mark foobar as an errand even though it does not have bin/run
      manifest_hash['jobs'].first['lifecycle'] = 'errand'

      manifest_hash
    end

    it 'returns 1 as exit code and mentions absence of bin/run' do
      deploy_simple(manifest_hash: manifest_hash)

      output, exit_code = bosh_runner.run('run errand foobar', {failure_expected: true, return_exit_code: true})

      expect(output).to match(
        %r{Error 450001: (.*Running errand script:.*jobs/foobar/bin/run: no such file or directory)}
      )
      expect(output).to include('Errand `foobar\' did not complete')
      expect(exit_code).to eq(1)
    end
  end

  context 'when errand does not exist in the deployment manifest' do
    with_reset_sandbox_before_each

    it 'returns 1 as exit code and mentions not found errand' do
      deploy_simple

      output, exit_code = bosh_runner.run('run errand unknown-errand-name',
                                          {failure_expected: true, return_exit_code: true})

      expect(output).to include('Errand `unknown-errand-name\' doesn\'t exist')
      expect(output).to include('Errand `unknown-errand-name\' did not complete')
      expect(exit_code).to eq(1)
    end
  end

  context 'when deploying sized resource pools with insufficient capacity for all errands' do
    with_reset_sandbox_before_each

    let(:manifest_hash) do
      manifest_hash = Bosh::Spec::Deployments.simple_manifest

      # Errand with sufficient resources
      manifest_hash['jobs'] << {
        'name'          => 'errand1-name',
        'template'      => 'errand1',
        'lifecycle'     => 'errand',
        'resource_pool' => 'a',
        'instances'     => 1,
        'networks'      => [{ 'name' => 'a' }],
        'properties' => {},
      }

      # Expand resource pool capacity to cover added errand
      total_instance_count = manifest_hash['jobs'].inject(0) { |sum, job| sum + job['instances'] }
      manifest_hash['resource_pools'].first['size'] = total_instance_count

      # Errand with insufficient resources
      manifest_hash['jobs'] << {
        'name'          => 'errand2-name',
        'template'      => 'errand1',
        'lifecycle'     => 'errand',
        'resource_pool' => 'a',
        'instances'     => 2,
        'networks'      => [{ 'name' => 'a' }],
        'properties' => {},
      }

      manifest_hash
    end

    it 'returns 1 as exit code and mentions insufficient resources' do
      output, exit_code = deploy_simple(manifest_hash: manifest_hash, failure_expected: true, return_exit_code: true)

      capacity = manifest_hash['resource_pools'].first['size']
      expect(output).to include("Resource pool `a' is not big enough: #{capacity + 1} VMs needed, capacity is #{capacity}")
      expect(exit_code).to eq(1)
    end
  end

  def expect_running_vms(job_name_index_list)
    vms = director.vms
    expect(vms.map(&:job_name_index)).to match_array(job_name_index_list)
    expect(vms.map(&:last_known_state).uniq).to eq(['running'])
  end
end
