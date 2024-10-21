%% Description -----------------------------------------------------------
% Copyright 2023 Zurich Instruments AG
% This example demonstrates how to poll data from a GHFLI demodulator.

% Clear and close everything
close all; clear; clc;

%% User settings ---------------------------------------------------------

% Serial number of instrument in its rear panel.
device = 'dev10000';

% Interface between the instrument and the host computer: '1GbE'
interface = '1GbE';

% IP address of LabOne data server host, e.g., 'localhost' or '169.254.1.2'
host = 'localhost';

% Rate (Sa/s) of data transfer from the instrument to the host computer
data_rate = 2000;

% Acquisition time duration (s)
measurement_duration = 6;  

%% Connection to instrument ----------------------------------------------

% Close current API sessions
clear ziDAQ

% Create an API session to the data server
port = 8004;        % Data server port to communicate
api_level = 6;      % Maximum API level supported by the instrument
ziDAQ('connect', host, port, api_level);

% Establish a connection between data server and instrument
ziDAQ('connectDevice', device, interface);

%% Instrument settings ---------------------------------------------------

% Define all the settings in a cell
device_settings = {
    % Adjust the data rate of demodulator 1
    ['/' device '/demods/0/rate'], data_rate
    % Enable continuous data streaming of demodulator 1
    ['/' device '/demods/0/trigger/triggeracq'], 0
    % Enable the data transfer from demodulator 1 to data server
    ['/' device '/demods/0/enable'], 1
};

% Apply all the settings to the device via a transaction
ziDAQ('set', device_settings);

%% Initial variables -----------------------------------------------------

% Time difference (s) between two consecutive timestamp tics
dt_device = ziDAQ('getDouble', ['/' device '/system/properties/timebase']);

% Timeout of the poll loop
timeout = 1.5 * measurement_duration;

% Time duration of a single poll execution (s)
poll_duration = 1.5;

% Timeout of a single poll execution (ms)
poll_timeout = 500;

% Variables to record time and signal quadrature components X and Y
time = [];
X = [];
Y = [];

% Current timestamp of the instrument
timestamp_initial = double(ziDAQ('getInt', ['/' device '/status/time']));

%% Subscription to data path ---------------------------------------------

% Subscribe to the signal path of demodulator 1 for acquisition
path = ['/' device '/demods/0/sample'];
ziDAQ('subscribe', path);

%% Poll data -------------------------------------------------------------

% Polling data from the signal path
fprintf('\nStart acquisition of data for %.1f s...\n\n', measurement_duration);

% Run the poll loop
measured_sofar = 0;
t0 = tic;
while measured_sofar < measurement_duration
    data = ziDAQ('poll', poll_duration, poll_timeout);
    if ~isempty(data)
        x = [];
        y = [];
        bursts = [data.(device).demods(1).sample.vector(:).segments];
        x = [bursts(:).x];
        y = [bursts(:).y];
        signal_length = length(x);
        dt = double(bursts(1).dt);
        timestamp = double(bursts(1).timestamp);
        initial_time = (double(bursts(1).timestamp) - timestamp_initial) * dt_device;
        time_interval = initial_time + (0:1:(signal_length-1)) * dt * dt_device;
        time = [time time_interval];
        X = [X x];
        Y = [Y y];
        measured_sofar = time(end) - time(1);
    end
    elapsed_time = toc(t0);
    if elapsed_time > timeout
        fprintf('\nTimeout: Data acquisition of %.1f s could not be finished within %.1f s.\n\n', measurement_duration, elapsed_time);
        break;
    end
    fprintf('Elapsed time: %.2f s.\n', elapsed_time);
    fprintf('So far acquisition of %.2f s out of %.1f s is done.\n', measured_sofar, measurement_duration);
    if measured_sofar >= measurement_duration
        fprintf('\nAcquisition is complete.\n\n');
    end 
end

%% Unsubscription --------------------------------------------------------

% Unsubscribe from all signal paths
ziDAQ('unsubscribe', '*');

%% Disconnection ---------------------------------------------------------

% Disconnect the device from data server
% ziDAQ('disconnectDevice', device);

% Destroy the API session
clear ziDAQ

%% Plotting --------------------------------------------------------------

% Plot the amplitude and phase of the measured signal
if ~isempty(time)
    plot_amp_phase(time,X,Y);
end

function plot_amp_phase(t,x,y)

    % Adjust the time axis to start at origin
    t = t - t(1);

    % Convertion from quadrature components to polar components
    r = abs(x + 1i*y);
    phase = atan2d(y,x);
    
    % Visualization
    figure('Name','Demodulation','NumberTitle','on');
    set(gca,'FontSize',12,'LineWidth',2,'Color',[1 1 1],'Box','on');
    subplot(2,1,1)
    h = plot(t,r);
    set(h,'LineWidth',1,'LineStyle','-','Color',[0 0.4470 0.7410])
    xlabel('Time  (s)','fontsize',10,'fontweight','n','color','k');
    ylabel('Amplitude  (V)','fontsize',10,'fontweight','n','color','k');
    grid on
    title('Signal: Amplitude and Phase')
    subplot(2,1,2)
    h = plot(t,phase);
    set(h,'LineWidth',1 ,'LineStyle','-','Color',[0.6350 0.0780 0.1840])
    xlabel('Time  (s)','fontsize',10,'fontweight','n','color','k');
    ylabel('Phase  (deg)','fontsize',10,'fontweight','n','color','k');
    grid on

end
% ------------------------------------------------------------------------
