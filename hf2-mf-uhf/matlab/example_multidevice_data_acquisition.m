function example_multidevice_data_acquisition(device_ids, varargin)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% EXAMPLE_MULTIDEVICE_DATA_ACQUISITION demonstrates how to synchronize 2 or
% more MFLI instruments or 2 or more UHFLI instruments using the MDS capability of LabOne.
% It also measures the temporal response of demodulator filters of both
% both instruments using the Data Acquisition (DAQ) Module.
%
% USAGE EXAMPLE_MULTIDEVICE_DATA_ACQUISITION({LEADER_ID, FOLLOWER_ID})
%
% LEADER_ID and FOLLOWER_ID should be a string, e.g. 'dev1000' or 'uhf-dev1000'.
%
% NOTE This example can only be run when either two or more UHF or 2 or more MF instruments
% are available.
%
% Arguments:
%   device_ids (char cell array): The IDs of the devices to run the example with. For
%     example, {'dev1000','dev2000'}. The first device is treated as the
%     leader device.
%   synchronize (bool, optional): Specify if multi-device synchronization will
%     be started and stopped before and after the data acquisition.
%     server (char array, optional): The IP-address of the LabOne Data
%     Server. If not specified, the default is 'localhost'.
%
% Hardware configuration:
% The cabling of the instruments must follow the MDS cabling depicted in
% the MDS tab of LabOne.
% Additionally, Signal Out 1 of the leader device is split into Signal In 1 of the leader and followers.
%
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
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
%
% NOTE The possible choice of the parameters:
% - synchronize (synchronize the devices before aquiring data)
p = inputParser;
isbool = @(x) islogical(x);
is_text = @(x) ischar(x);
p.addParamValue('synchronize', true, isbool);
p.addParamValue('server', 'localhost', is_text);
p.parse(varargin{:});
synchronize = p.Results.synchronize;
server_address = p.Results.server;

% Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
if ~(exist('ziDAQ', 'file') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
    fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
    fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
    fprintf('This can be found in the API subfolder of your LabOne installation.\n');
    fprintf('On Windows this is typically:\n');
    fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
    return
end
clear ziDAQ;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Check if the device IDs exist
if ~exist('device_ids', 'var')
    error(['No list of device_ids specified. The first argument to the ' ...
           'example should be the device IDs on which to run the example, ' ...
           'e.g. {''dev1000'', ''dev2000''}. Two devices are required'])
end
if length(device_ids) < 2
    error(['Two device IDs must be specified. e.g. {''dev1000'', ''dev2000''}']);
end
leader_id = device_ids{1};
follower_id = device_ids{2};
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Connection to the data server and devices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Connection to the local server 'localhost' = '127.0.0.1'
apilevel = 6;
ziDAQ('connect', server_address', 8004, apilevel);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Leader and follower device ID
deviceSerials = cellfun(@(devId) lower(ziDAQ('discoveryFind', devId)), device_ids, 'UniformOutput', false);
deviceProps = cellfun(@(devSer) ziDAQ('discoveryGet', devSer), deviceSerials);
devices = strjoin(deviceSerials, ',');
% Switching between MFLI and UHFLI
leaderDeviceType = deviceProps(1).devicetype;
if all(arrayfun(@(prop) isequal(leaderDeviceType, prop.devicetype) && strcmpi(leaderDeviceType, 'UHFLI'), deviceProps));
  arrayfun(@(prop) ziDAQ('connectDevice', lower(prop.deviceid), prop.interfaces{1}), deviceProps);
elseif all(arrayfun(@(prop) ~isempty(strfind(prop.devicetype, 'MF')), deviceProps));
  arrayfun(@(prop) ziDAQ('connectDevice', lower(prop.deviceid), '1GbE'), deviceProps);
else
    error('This example needs at least 2 MFLI instruments or at least 2 UHFLI instruments');
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Disable all available outputs, demods, ...
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
cellfun(@(dev) ziDisableEverything(dev), deviceSerials, 'UniformOutput', false);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Device synchronization
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if synchronize
  fprintf('Synchronizing devices %s ...\n', devices);
  mds = ziDAQ('multiDeviceSyncModule');
  ziDAQ('set', mds, 'start', 0);
  ziDAQ('set', mds, 'group', 0)
  ziDAQ('execute', mds);
  ziDAQ('set', mds, 'devices', devices);
  ziDAQ('set', mds, 'start', 1)

  timeout = 20;
  tic;
  start = toc;
  status = 0;
  while status ~= 2
      pause(0.2)
      status = ziDAQ('getInt', mds, 'status');
      if status == -1
        error('Error during device sync');
      end
      if (toc - start) > timeout
        error('Timeout during device sync');
      end
  end
  fprintf('Devices successfully synchronized.\n');
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Device settings
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define some other helper parameters.
demod_c = '0'; % demod channel, for paths on the device
% demod_idx = str2double(demod_c)+1; % 1-based indexing, to access the data
out_c = '0'; % signal output channel
% Get the value of the instrument's default Signal Output mixer channel.
out_mixer_c = num2str(ziGetDefaultSigoutMixerChannel(deviceProps(1), str2double(out_c)));
in_c = '0'; % signal input channel
osc_c = '0'; % oscillator

time_constant = 1.0e-3; % [s]
demod_rate = 10e3; % [Sa/s]
filter_order = 8;
osc_freq = 1e3; % [Hz]
out_amp = 0.600;  % [V]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Leader device settings
leader = deviceSerials{1};
ziDAQ('setInt', ['/' leader '/sigouts/' out_c '/on'], 1);
ziDAQ('setDouble', ['/' leader '/sigouts/' out_c '/range'], 1);
ziDAQ('setDouble', ['/' leader '/sigouts/' out_c '/amplitudes/' out_mixer_c], out_amp);
ziDAQ('setDouble', ['/' leader '/demods/' demod_c '/phaseshift'], 0);
ziDAQ('setInt', ['/' leader '/demods/' demod_c '/order'], filter_order);
ziDAQ('setDouble', ['/' leader '/demods/' demod_c '/rate'], demod_rate);
ziDAQ('setInt', ['/' leader '/demods/' demod_c '/harmonic'], 1);
ziDAQ('setInt', ['/' leader '/demods/' demod_c '/enable'], 1);
ziDAQ('setInt', ['/' leader '/demods/' demod_c '/oscselect'], str2double(osc_c));
ziDAQ('setInt', ['/' leader '/demods/' demod_c '/adcselect'], str2double(in_c));
ziDAQ('setDouble', ['/' leader '/demods/' demod_c '/timeconstant'], time_constant);
ziDAQ('setDouble', ['/' leader '/oscs/' osc_c '/freq'], osc_freq);
ziDAQ('setInt', ['/' leader '/sigins/' in_c '/imp50'], 1);
ziDAQ('setInt', ['/' leader '/sigins/' in_c '/ac'], 0);
ziDAQ('setDouble', ['/' leader '/sigins/' in_c '/range'], out_amp/2);
ziDAQ('setDouble', ['/' leader '/sigouts/' out_c '/enables/' out_mixer_c], 0);
% Follower device settings
for ii = 2:length(deviceSerials)
  follower = deviceSerials{ii};
  ziDAQ('setDouble', ['/' follower '/demods/' demod_c '/phaseshift'], 0);
  ziDAQ('setInt', ['/' follower '/demods/' demod_c '/order'], filter_order);
  ziDAQ('setDouble', ['/' follower '/demods/' demod_c '/rate'], demod_rate);
  ziDAQ('setInt', ['/' follower '/demods/' demod_c '/harmonic'], 1);
  ziDAQ('setInt', ['/' follower '/demods/' demod_c '/enable'], 1);
  ziDAQ('setInt', ['/' follower '/demods/' demod_c '/oscselect'], str2double(osc_c));
  ziDAQ('setInt', ['/' follower '/demods/' demod_c '/adcselect'], str2double(in_c));
  ziDAQ('setDouble', ['/' follower '/demods/' demod_c '/timeconstant'], time_constant);
  ziDAQ('setDouble', ['/' follower '/oscs/' osc_c '/freq'], osc_freq);
  ziDAQ('setInt', ['/' follower '/sigins/' in_c '/imp50'], 1);
  ziDAQ('setInt', ['/' follower '/sigins/' in_c '/ac'], 0);
  ziDAQ('setDouble', ['/' follower '/sigins/' in_c '/range'], out_amp/2);
end
% Synchronization
ziDAQ('sync'); pause(1);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% measuring the transient state of demodulator filters using DAQ module
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DAQ module
% Create a Data Acquisition Module instance, the return argument is a handle to the module
daq = ziDAQ('dataAcquisitionModule');
% Configure the Data Acquisition Module
% Device on which trigger will be performed
ziDAQ('set', daq, 'device', leader)
% The number of triggers to capture (if not running in endless mode).
ziDAQ('set', daq, 'count', 1);
ziDAQ('set', daq, 'endless', 0);
% 'grid/mode' - Specify the interpolation method of
%   the returned data samples.
%
% 1 = Nearest. If the interval between samples on the grid does not match
%     the interval between samples sent from the device exactly, the nearest
%     sample (in time) is taken.
%
% 2 = Linear interpolation. If the interval between samples on the grid does
%     not match the interval between samples sent from the device exactly,
%     linear interpolation is performed between the two neighbouring
%     samples.
%
% 4 = Exact. The subscribed signal with the highest sampling rate (as sent
%     from the device) defines the interval between samples on the DAQ
%     Module's grid. If multiple signals are subscribed, these are
%     interpolated onto the grid (defined by the signal with the highest
%     rate, "highest_rate"). In this mode, duration is
%     read-only and is defined as num_cols/highest_rate.
grid_mode = 2;
ziDAQ('set', daq, 'grid/mode', grid_mode);
%   type:
%     NO_TRIGGER = 0
%     EDGE_TRIGGER = 1
%     DIGITAL_TRIGGER = 2
%     PULSE_TRIGGER = 3
%     TRACKING_TRIGGER = 4
%     HW_TRIGGER = 6
%     TRACKING_PULSE_TRIGGER = 7
%     EVENT_COUNT_TRIGGER = 8
ziDAQ('set', daq, 'type', 1);
%   triggernode, specify the triggernode to trigger on.
%     SAMPLE.X = Demodulator X value
%     SAMPLE.Y = Demodulator Y value
%     SAMPLE.R = Demodulator Magnitude
%     SAMPLE.THETA = Demodulator Phase
%     SAMPLE.AUXIN0 = Auxilliary input 1 value
%     SAMPLE.AUXIN1 = Auxilliary input 2 value
%     SAMPLE.DIO = Digital I/O value
triggernode = ['/' leader '/demods/' demod_c '/sample.r'];
ziDAQ('set', daq, 'triggernode', triggernode);
%   edge:
%     POS_EDGE = 1
%     NEG_EDGE = 2
%     BOTH_EDGE = 3
ziDAQ('set', daq, 'edge', 1)
demod_rate = ziDAQ('getDouble', ['/' leader '/demods/' demod_c '/rate']);
% Exact mode: To preserve our desired trigger duration, we have to set
% the number of grid columns to exactly match.
trigger_duration = time_constant*30;
sample_count = demod_rate*trigger_duration;
ziDAQ('set', daq, 'grid/cols', sample_count);
% The length of each trigger to record (in seconds).
ziDAQ('set', daq, 'duration', trigger_duration);
ziDAQ('set', daq, 'delay', -trigger_duration/4);
% Do not return overlapped trigger events.
ziDAQ('set', daq, 'holdoff/time', 0);
ziDAQ('set', daq, 'holdoff/count', 0);
ziDAQ('set', daq, 'level', out_amp/6)
% The hysterisis is effectively a second criteria (if non-zero) for triggering
% and makes triggering more robust in noisy signals. When the trigger `level`
% is violated, then the signal must return beneath (for positive trigger edge)
% the hysteresis value in order to trigger.
ziDAQ('set', daq, 'hysteresis', 0.01)
% synchronizing the settings
ziDAQ('sync');
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Recording
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Subscribe to the demodulators
ziDAQ('unsubscribe', daq, '*');
cellfun(@(dev) ziDAQ('subscribe', daq, ['/' dev '/demods/' demod_c '/sample.r']), deviceSerials);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Execute the module
ziDAQ('execute', daq);
% Send a trigger
ziDAQ('setDouble', ['/' leader '/sigouts/' out_c '/enables/' out_mixer_c], 1);
% Reading the result
result = [];
while ~ziDAQ('finished', daq)
  pause(1);
  result = ziDAQ('read', daq);
  fprintf('Progress %0.0f%%\n', ziDAQ('progress', daq) * 100);
end
% Turn off the trigger and output
ziDAQ('setDouble', ['/' leader '/sigouts/' out_c '/enables/' out_mixer_c], 0);
ziDAQ('setInt', ['/' leader '/sigouts/' out_c '/on'], 0);
% Finish the DAQ module
ziDAQ('finish', daq);

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', daq);
% Stopping the MDS module
if synchronize
  ziDAQ('set', mds, 'start', 0);
  ziDAQ('finish', mds);

  ziDAQ('clear', mds);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Extracting and plotting the data
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
plotData = struct([]);
for ii = 1:length(deviceSerials)
  dev = deviceSerials{ii};
  clockbase = double(ziDAQ('getDouble', ['/' dev '/clockbase']));
  timestamp = result.(dev).demods.sample_r{1}.timestamp;
  plotData(ii).time = (double(timestamp) - double(timestamp(1)))/clockbase;
  plotData(ii).demodAmp = result.(dev).demods.sample_r{1}.value;
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Disconnecting the instruments from the dataserver
% cellfunc(@(dev) ziDAQ('disconnectDevice', dev));
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Plotting
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
figure('Name','DAQ','NumberTitle','on');
set(gca,'FontSize',12,...
    'LineWidth',2,...
    'Color',[1 1 1],...
    'Box','on');
subplot(2,1,1)
h = plot(plotData(1).time*1E3, plotData(1).demodAmp*1E3);
set(h,'LineWidth',2.5,'LineStyle','-','Color','b')
ylabel('Amplitude [mV]','fontsize',12,'color','k');
h = legend('Leader');
set(h,'Box','on','Color','w','Location','SouthEast','FontSize',12)
title('Transient Measurement by DAQ Mdule')
grid on

subplot(2,1,2)
for ii = 2:length(deviceSerials)
  h = plot(plotData(ii).time*1E3, plotData(ii).demodAmp*1E3);
  set(h,'LineWidth',2.5,'LineStyle','-','Color','r')
  h = legend('Follower');
  set(h,'Box','on','Color','w','Location','SouthEast','FontSize',12)
  xlabel('Time [ms]','fontsize',12,'fontweight','n','color','k');
  ylabel('Amplitude [mV]','fontsize',12,'fontweight','n','color','k');
  grid on
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
figure('Name','MDS','NumberTitle','on');
set(gca,'FontSize',12,...
    'LineWidth',2,...
    'Color',[1 1 1],...
    'Box','on');
subplot(2,1,1)
h = plot(plotData(1).time*1E3, plotData(1).demodAmp*1E3);
set(h,'LineWidth',2.0,'LineStyle','-','Color','b')
hold on
for ii = 2:length(deviceSerials)
  h = plot(plotData(ii).time*1E3, plotData(ii).demodAmp*1E3);
  set(h,'LineWidth',1.5,'LineStyle','-.','Color','r')
  ylabel('Amplitude [mV]','fontsize',12,'color','k');
  h = legend('Leader', 'Follower');
  set(h,'Box','on','Color','w','Location','SouthEast','FontSize',12)
  title('Transient Measurement by DAQ Mdule')
  grid on
end

subplot(2,1,2)
for ii = 2:length(deviceSerials)
  h = plot(plotData(ii).time*1E3, (plotData(1).time - plotData(ii).time)*1E3);
  set(h,'LineWidth',2.5,'LineStyle','--','Color','m')
  title('Time Difference between Leader and Follower')
  xlabel('Time [ms]','fontsize',12,'fontweight','n','color','k');
  ylabel('Time difference [ms]','fontsize',12,'fontweight','n','color','k');
  grid on
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end
