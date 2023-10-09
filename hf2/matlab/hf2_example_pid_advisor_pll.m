function result = hf2_example_pid_advisor_pll(device_id, varargin)
% HF2_EXAMPLE_PID_ADVISOR optimise PLL config with the PID Advisor
%
% USAGE SAMPLE = HF2_EXAMPLE_PID_ADVISOR(DEVICE_ID)
%
% Setup the PID Advisor and calculate optimal settings for internal
% PLL mode on the device specified by DEVICE_ID. DEVICE_ID should be a
% string, e.g. 'dev1000' or 'uhf-dev1000'.
%
% NOTE This example can only be ran with HF2 Instruments with the PLL
% Option enabled.
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% with a BNC cable.
%
% NOTE Please ensure that the ziDAQ folders 'Driver' and 'Utils' are in your
% Matlab path. To do this (temporarily) for one Matlab session please navigate
% to the ziDAQ base folder containing the 'Driver', 'Examples' and 'Utils'
% subfolders and run the Matlab function ziAddPath().
% >>> ziAddPath;
%
% Use either of the commands:
% >>> help ziDAQ
% >>> doc ziDAQ
% in the Matlab command window to obtain help on all available ziDAQ commands.
%
% Copyright 2008-2018 Zurich Instruments AG

clear ziDAQ;

if ~exist('device_id', 'var')
  error(['No value for device_id specified. The first argument to the ' ...
    'example should be the device ID on which to run the example, ' ...
    'e.g. ''dev1000'' or ''uhf-dev1000''.'])
end

% Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
if ~(exist('ziDAQ') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
  fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
  fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
  fprintf('This can be found in the API subfolder of your LabOne installation.\n');
  fprintf('On Windows this is typically:\n');
  fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
  return
end

% The API level supported by this example.
apilevel_example = 1;
% Create an API session; connect to the correct Data Server for the device.
required_err_msg = ['This example only runs with HF2 Instruments with the ' ...
                    'PLL Option enabled.'];
[device, props] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', 'HF2.*', ...
                                     'required_options', {'PLL'}, ...
                                     'required_err_msg', required_err_msg);
ziApiServerVersionCheck();

%% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
default_target_bw = 10e3;
p = inputParser;
isnonnegscalar = @(x) isnumeric(x) && isscalar(x) && (x > 0);
p.addParamValue('target_bw', default_target_bw, isnonnegscalar);
p.parse(varargin{:});

pll_center_frequency = 1.0e6;

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

% Start of the PID advisor module
advisor = ziDAQ('pidAdvisor');

%% Setup of PID advisor
ziDAQ('set', advisor, 'device', device)
% Turn off auto-calc on param change. Enabled
% auto calculation can be used to automatically
% update response data based on user input.
ziDAQ('set', advisor, 'auto', 0);
ziDAQ('set', advisor, 'pid/targetbw', p.Results.target_bw)
% PID advising mode (bit coded)
% bit 0: optimize/tune P
% bit 1: optimize/tune I
% bit 2: optimize/tune D
% Example: mode = 3: Only optimize/tune PI
ziDAQ('set', advisor, 'pid/mode', 3)
% PLL index to use (first PLL of device: 0)
ziDAQ('set', advisor, 'index', 0);
% DUT model
% source = 1: Lowpass first order
% source = 2: Lowpass second order
% source = 3: Resonator frequency
% source = 4: Internal PLL
% source = 5: VCO
% source = 6: Resonator amplitude
dut_source = 4;
ziDAQ('set', advisor, 'dut/source', 4)
if dut_source == 4
    % Since there are two possiblities to configure a PLL on an HF2 (via
    % the PLL or the PID), we need to additionally specify that the
    % PID Advisor should model the HF2's PLL.
    ziDAQ('set', advisor, 'pid/type', 'pll');
    % The PID Advisor is appropriate for optimizing the HF2's PLL
    % parameters (pid/type set to 'pll') or the HF2's PID
    % parameters (pid/type set to 'pid').
end
% IO Delay of the feedback system describing the earliest response
% for a step change. This parameter does not affect the shape of
% the DUT transfer function
ziDAQ('set', advisor, 'dut/delay', 0.0)
% Start values for the PID optimization. Zero
% values will initate a guess. Other values can be
% used as hints for the optimization process.
% Following parameters are not required for the internal PLL model
% ziDAQ('set', advisor, 'dut/gain', 1)
% ziDAQ('set', advisor, 'dut/bw', 1000)
% ziDAQ('set', advisor, 'dut/fcenter', 15e6)
% ziDAQ('set', advisor, 'dut/damping', 0.1)
% ziDAQ('set', advisor, 'dut/q', 10e3)
ziDAQ('set', advisor, 'pid/p', 0);
ziDAQ('set', advisor, 'pid/i', 0);
ziDAQ('set', advisor, 'pid/d', 0);
ziDAQ('set', advisor, 'calculate', 0)

% Start the module thread
ziDAQ('execute', advisor);

%% Advise
fprintf('Starting advising. Optimization process may run up to a minute...\n');
ziDAQ('set', advisor, 'calculate', 1)
calculate = 1;
timeout = 60; % [s]
tic;
while calculate == 1
  pause(0.5)
  calculate = ziDAQ('getInt', advisor, 'calculate');
  if toc > timeout
    ziDAQ('finish', advisor);
    ziDAQ('clear', advisor);
    error('PID advising failed due to timeout.')
  end
end
fprintf('Advice took %0.1fs\n', toc);

%% Get all calculated parameters
result = ziDAQ('get', advisor, '*');

if ~isempty(result)
  %% Transfer the PID coefficients to the device's PLL
  % Now copy the values from the PID Advisor to the device's PLL.
  ziDAQ('set', advisor, 'todevice', 1)
  % Note: On HF2 devices the PLL is an additional hardware entity on the
  % device (it is not combined on the device with the PID), so we need
  % to copy the parameters to the appropriate nodes in the PLLS device
  % branch, not to the PIDS branch.
  % Let's have a look at the optimised gain parameters.
  fprintf('The pidAdvisor calculated the following gains,  P: %f, I: %f, D: %f.\n', ...
          result.pid.i, result.pid.d, result.pid.d);
  % You may now also want to enable the device's PLL:
  % ziDAQ('setInt', ['/' device '/plls/0/enable'], 1)

  %% Plot calculated PID response
  complexData = result.bode.x + 1i * result.bode.y;
  subplot(3, 1, 1)
  h = semilogx(result.bode.grid, 20 * log10(abs(complexData)));
  set(h, 'Color', 'black')
  set(h, 'LineWidth', 1.5)
  box on
  grid on
  xlabel('Frequency [Hz]')
  ylabel('Bode Gain [dB]')
  title(sprintf('Calculated model response for internal PLL with P = %0.0f, I = %0.0f, D = %0.5f and bandwidth %0.0fkHz\n', result.pid.p, result.pid.i, result.pid.d, result.bw * 1e-3))
  subplot(3, 1, 2)
  h = semilogx(result.bode.grid, angle(complexData) / pi * 180);
  set(h, 'Color', 'black')
  set(h, 'LineWidth', 1.5)
  box on
  grid on
  xlabel('Frequency [Hz]')
  ylabel('Bode Phase [deg]')
  subplot(3, 1, 3)
  h = plot(result.step.grid * 1e6, result.step.x);
  set(h, 'Color', 'black')
  set(h, 'LineWidth', 1.5)
  box on
  grid on
  xlabel('Time [us]')
  ylabel('Step Response')
end

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', advisor);

end
