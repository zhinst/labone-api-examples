function data = example_poll_impedance(device_id, varargin)
% EXAMPLE_AUTORANGING_IMPEDANCE Demonstrate how to obtain impedance
% data using ziDAQServer's blocking (synchronous) poll() command.
%
% USAGE DATA = EXAMPLE_POLL_IMPEDANCE(DEVICE_ID)
%
% The example demonstrates how to poll impedance data.
% DEVICE_ID should be a string, e.g., 'dev1000'.
%
% NOTE Additional configuration: Connect Impedance Testfixture and attach a 1kOhm
% resistor
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
           'e.g. ''dev1000''.'])
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
apilevel_example = 6;
% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, apilevel_example);
ziApiServerVersionCheck();

% This example requires an MF device with IA option.
if ~ismember('IA', props.options)
    installed_options_str = ''; % Note: strjoin() unavailable in Matlab 2009.
    for option=props.options
      installed_options_str = [installed_options_str, ' ', option{1}];
    end
    error(['Required option set not satisfied. This example requires an MF ' ...
           'Instrument with the IA Option installed. Device `%s` reports ' ...
           'devtype `%s` and options `%s`.'], ...
          device, props.devicetype, installed_options_str);
end

% We use the auto-range example to perform some basic device configuration
% and wait until signal input ranges have been configured by the device.
example_autoranging_impedance(device);

% The impedance channel to use.
imp_c = '0';
imp_index = 1;

% Subscribe to the impedance sample
% The Data Server's node tree uses 0-based indexing; Matlab uses
% 1-based indexing:
imp_node_path = ['/' device, '/imps/' imp_c '/sample'];
ziDAQ('subscribe', imp_node_path);

% Sleep for demonstration purposes: Allow data to accumulate in the data
% server's buffers for one second: poll() will not only return the data
% accumulated during the specified poll_length, but also for data
% accumulated since the subscribe() or the previous poll.
pause(1.0);

poll_duration = 0.02;
poll_timeout = 100;
data = ziDAQ('poll', poll_duration, poll_timeout);

% Unsubscribe from all paths.
ziDAQ('unsubscribe', '*');

if ziCheckPathInData(data, imp_node_path)
    sample = data.(device).imps(imp_index).sample;

    % Get the sampling rate of the device's ADCs, the device clockbase in order to convert the sample's timestamps to
    % seconds.
    clockbase = double(ziDAQ('getInt', ['/' device '/clockbase']));
    t0 = double(sample.timestamp(1));
    dt_seconds = (double(sample.timestamp(end)) - t0)/clockbase;
    num_samples= length(sample.timestamp);

    fprintf('Poll returned %d samples of impedance data spanning %.3f s.\n', num_samples, dt_seconds)
    fprintf('Average measured resistance: %.3e Ohm.\n', mean(sample.param0))
    fprintf('Average measured capacitance: %.3e F.\n', mean(sample.param1))

    t = (double(sample.timestamp) - t0)/clockbase;

    figure(1)
    clf;
    title('\\bImpedance Parameter Data');
    hold on;
    ax1 = subplot(2, 1, 1);
    plot(t, sample.param0);
    grid on;
    ylabel('Resistance [Ohm]')
    ax2 = subplot(2, 1, 2);
    plot(t, sample.param1);
    grid on;
    ylabel('Capcitance [F]')
    xlabel('Time (s)')
    x = xlim(ax1);
    xlim(ax1, [min(x) max(x)]);
    linkaxes([ax1, ax2], 'x')
else
    error(['Poll did not return the expected data (', imp_node_path, ') - data transfer rate is 0?']);
end
