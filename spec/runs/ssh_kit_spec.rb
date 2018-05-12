require "spec_helper"

RSpec.describe Runbook::Runs::SSHKit do
  subject { Runbook::Runs::SSHKit }
  let (:metadata_override) { {} }
  let (:parent) { Runbook::Entities::Step.new }
  let (:toolbox) { instance_double("Runbook::Toolbox") }
  let (:metadata) {
    {
      noop: false,
      auto: false,
      start_at: 0,
      toolbox: toolbox,
      depth: 1,
      index: 2,
      parent: parent,
      position: "3.3",
    }.merge(metadata_override)
  }

  describe "runbook__entities__assert" do
    let (:cmd) { "echo 'hi'" }
    let (:interval) { 7 }
    let (:object) do
      Runbook::Statements::Assert.new(cmd, interval: interval)
    end

    it "runs cmd until it returns true" do
      test_args = [:echo, "'hi'"]
      ssh_config = metadata[:parent].ssh_config
      expect(
        subject
      ).to receive(:with_ssh_config).with(ssh_config).and_call_original
      expect_any_instance_of(
        SSHKit::Backend::Abstract
      ).to receive(:test).with(*test_args).and_return(true)
      expect(subject).to_not receive(:sleep)

      subject.execute(object, metadata)
    end

    context "with cmd_ssh_config set" do
      let(:cmd_ssh_config) do
        {servers: ["host.stg"], parallelization: {}}
      end
      let (:object) do
        Runbook::Statements::Assert.new(
          cmd,
          cmd_ssh_config: cmd_ssh_config
        )
      end

      it "uses the cmd_ssh_config" do
        test_args = [:echo, "'hi'"]
        expect(
          subject
        ).to receive(:with_ssh_config).with(cmd_ssh_config).and_call_original
        expect_any_instance_of(
          SSHKit::Backend::Abstract
        ).to receive(:test).with(*test_args).and_return(true)
        expect(subject).to_not receive(:sleep)

        subject.execute(object, metadata)
      end
    end

    context "with raw true" do
      let(:raw) { true }
      let (:object) do
        Runbook::Statements::Assert.new(cmd, cmd_raw: raw)
      end

      it "runs runs test with the raw commmand string" do
        test_args = ["echo 'hi'"]
        expect_any_instance_of(
          SSHKit::Backend::Abstract
        ).to receive(:test).with(*test_args).and_return(true)

        subject.execute(object, metadata)
      end
    end

    context "when assertion times out" do
      let!(:time) { Time.now }
      let (:timeout) { 1 }
      before(:each) do
        expect(Time).to receive(:now).and_return(time, time + timeout + 1)
      end
      let (:object) do
        Runbook::Statements::Assert.new(cmd, timeout: timeout)
      end

      it "raises an ExecutionError" do
        test_args = [:echo, "'hi'"]
        expect_any_instance_of(
          SSHKit::Backend::Abstract
        ).to receive(:test).with(*test_args).and_return(false)
        expect(subject).to_not receive(:sleep)

        error_msg = "Error! Assertion `#{cmd}` failed"
        expect(toolbox).to receive(:error).with(error_msg)
        expect do
          subject.execute(object, metadata)
        end.to raise_error Runbook::Runner::ExecutionError, error_msg
      end

      context "when timeout_cmd is set" do
        let (:timeout_cmd) { "echo 'timed out!'" }
        let (:object) do
          Runbook::Statements::Assert.new(
            cmd,
            timeout: timeout,
            timeout_cmd: timeout_cmd
          )
        end

        before(:each) do
          test_args = [:echo, "'hi'"]
          expect_any_instance_of(
            SSHKit::Backend::Abstract
          ).to receive(:test).with(*test_args).and_return(false)
          allow(subject).to receive(:with_ssh_config).and_call_original
        end

        it "calls the timeout_cmd" do
          timeout_cmd_args = [:echo, "'timed out!'"]
          ssh_config = metadata[:parent].ssh_config
          expect(toolbox).to receive(:error)
          expect(
            subject
          ).to receive(:with_ssh_config).with(ssh_config).and_call_original
          expect_any_instance_of(
            SSHKit::Backend::Abstract
          ).to receive(:execute).with(*timeout_cmd_args)

          expect do
            subject.execute(object, metadata)
          end.to raise_error Runbook::Runner::ExecutionError
        end

        context "when timeout_cmd_ssh_config is set" do
          let (:timeout_cmd_ssh_config) do
            {servers: ["server01.stg"], parallelization: {}}
          end
          let (:object) do
            Runbook::Statements::Assert.new(
              cmd,
              timeout: timeout,
              timeout_cmd: timeout_cmd,
              timeout_cmd_ssh_config: timeout_cmd_ssh_config,
            )
          end

          it "calls the timeout_cmd with timeout_cmd_ssh_config" do
            timeout_cmd_args = [:echo, "'timed out!'"]
            expect(toolbox).to receive(:error)
            expect(subject).to receive(:with_ssh_config).
              with(timeout_cmd_ssh_config).
              and_call_original
            expect_any_instance_of(
              SSHKit::Backend::Abstract
            ).to receive(:execute).with(*timeout_cmd_args)

            expect do
              subject.execute(object, metadata)
            end.to raise_error Runbook::Runner::ExecutionError
          end
        end

        context "when timeout_cmd_raw is set to true" do
          let(:raw) { true }
          let (:object) do
            Runbook::Statements::Assert.new(
              cmd,
              timeout: timeout,
              timeout_cmd: timeout_cmd,
              timeout_cmd_raw: raw,
            )
          end


          it "calls the timeout_cmd with raw command string" do
            timeout_cmd_args = ["echo 'timed out!'"]
            expect(toolbox).to receive(:error)
            expect_any_instance_of(
              SSHKit::Backend::Abstract
            ).to receive(:execute).with(*timeout_cmd_args)

            expect do
              subject.execute(object, metadata)
            end.to raise_error Runbook::Runner::ExecutionError
          end
        end
      end
    end

    context "noop" do
      let(:metadata_override) { {noop: true} }

      it "outputs the noop text for the assert statement" do
        msg = "[NOOP] Assert: `#{cmd}` returns 0"
        msg += " (running every #{interval} second(s))"
        expect(toolbox).to receive(:output).with(msg)
        expect(subject).to_not receive(:with_ssh_config)

        subject.execute(object, metadata)
      end

      context "when timeout > 0" do
        let (:timeout) { 1 }
        let (:object) do
          Runbook::Statements::Assert.new(cmd, timeout: timeout)
        end

        it "outputs the noop text for the timeout" do
          msg = "after #{timeout} seconds, exit"
          allow(toolbox).to receive(:output)
          expect(toolbox).to receive(:output).with(msg)

          subject.execute(object, metadata)
        end

        context "when timeout_cmd is specified" do
          let (:timeout_cmd) { "./notify_everyone" }
          let (:object) do
            Runbook::Statements::Assert.new(
              cmd,
              timeout: timeout,
              timeout_cmd: timeout_cmd,
            )
          end

          it "outputs the noop text for the timeout_cmd" do
            msg = "after #{timeout} seconds, run `#{timeout_cmd}` and exit"
            allow(toolbox).to receive(:output)
            expect(toolbox).to receive(:output).with(msg)

            subject.execute(object, metadata)
          end
        end
      end
    end
  end

  describe "runbook__entities__command" do
    let (:cmd) { "echo 'hi'" }
    let (:object) { Runbook::Statements::Command.new(cmd) }

    before(:each) do
      allow(toolbox).to receive(:output)
    end

    it "runs cmd" do
      execute_args = [:echo, "'hi'"]
      ssh_config = metadata[:parent].ssh_config
      expect(
        subject
      ).to receive(:with_ssh_config).with(ssh_config).and_call_original
      expect_any_instance_of(
        SSHKit::Backend::Abstract
      ).to receive(:execute).with(*execute_args)

      subject.execute(object, metadata)
    end

    context "with ssh_config set" do
      let(:ssh_config) do
        {servers: ["host.stg"], parallelization: {}}
      end
      let (:object) do
        Runbook::Statements::Command.new(cmd, ssh_config: ssh_config)
      end

      it "uses the ssh_config" do
        execute_args = [:echo, "'hi'"]
        expect(
          subject
        ).to receive(:with_ssh_config).with(ssh_config).and_call_original
        expect_any_instance_of(
          SSHKit::Backend::Abstract
        ).to receive(:execute).with(*execute_args)

        subject.execute(object, metadata)
      end
    end

    context "with raw true" do
      let(:raw) { true }
      let (:object) do
        Runbook::Statements::Command.new(cmd, raw: raw)
      end

      it "executes the raw command string" do
        execute_args = ["echo 'hi'"]
        expect_any_instance_of(
          SSHKit::Backend::Abstract
        ).to receive(:execute).with(*execute_args)

        subject.execute(object, metadata)
      end
    end

    context "noop" do
      let(:metadata_override) { {noop: true} }

      it "outputs the noop text for the command statement" do
        msg = "[NOOP] Run: `#{cmd}`"
        expect(toolbox).to receive(:output).with(msg)
        expect(subject).to_not receive(:with_ssh_config)

        subject.execute(object, metadata)
      end
    end
  end
end