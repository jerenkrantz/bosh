require 'spec_helper'

describe 'delete release', type: :integration do
  with_reset_sandbox_before_each

  # ~25s
  it 'allows deleting a whole release' do
    target_and_login

    release_filename = spec_asset('valid_release.tgz')
    bosh_runner.run("upload release #{release_filename}")

    out = bosh_runner.run('delete release appcloud')
    expect(out).to match regexp('Deleted `appcloud')

    expect_output('releases', <<-OUT)
    No releases
    OUT
  end

  # ~22s
  it 'allows deleting a particular release version' do
    target_and_login

    release_filename = spec_asset('valid_release.tgz')
    bosh_runner.run("upload release #{release_filename}")

    out = bosh_runner.run('delete release appcloud 0.1')
    expect(out).to match regexp('Deleted `appcloud/0.1')
  end

  it 'fails to delete release in use but deletes a different release' do
    target_and_login

    Dir.chdir(ClientSandbox.test_release_dir) do
      bosh_runner.run_in_current_dir('create release')
      bosh_runner.run_in_current_dir('upload release')

      # change something in ClientSandbox.test_release_dir
      FileUtils.touch(File.join('src', 'bar', 'pretend_something_changed'))

      bosh_runner.run_in_current_dir('create release --force')
      bosh_runner.run_in_current_dir('upload release')
    end

    bosh_runner.run("upload stemcell #{spec_asset('valid_stemcell.tgz')}")

    deployment_manifest = yaml_file('simple', Bosh::Spec::Deployments.simple_manifest)
    bosh_runner.run("deployment #{deployment_manifest.path}")

    bosh_runner.run('deploy')

    out = bosh_runner.run('delete release bosh-release', failure_expected: true)
    expect(out).to match /Error 30007: Release `bosh-release' is still in use/

    out = bosh_runner.run('delete release bosh-release 0.2-dev')
    expect(out).to match %r{Deleted `bosh-release/0.2-dev'}
  end
end
