function uhf_example_awg_sourcefile(device_id, varargin)
% UHF_EXAMPLE_AWG_SOURCEFILE demonstrates how to connect to a
% Zurich Instruments Arbitrary Waveform Generator and compile/upload
% an AWG program to the instrument.
%
% USAGE UHF_EXAMPLE_AWG_SOURCEFILE(DEVICE_ID)
% USAGE UHF_EXAMPLE_AWG_SOURCEFILE(DEVICE_ID, FILE_NAME)
%
% DEVICE_ID should be a string, e.g., 'dev1000' or 'uhf-dev1000'.
% FILE_NAME is the name of the SeqC file without a suffix.
%
% NOTE This example can only be ran on UHF instruments with the AWG option
% enabled or on UHFAWG instruments.
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
if ~(exist('ziDAQ', 'file') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
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
required_err_msg = ['This example can only be ran on either a UHFAWG or' ...
                    'a UHF with the AWG option enabled.'];
[device, props] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', 'UHF', ...
                                     'required_err_msg', required_err_msg);
if (strcmpi('UHFLI', props.devicetype) == 1) &&...
        ~any(cellfun(@(x) ~isempty(x), strfind(props.options,'AWG')))
    error(['Required option set not satisfied. This example only ' ...
           'runs on UHFLI with the AWG Option installed.'],device)
end
ziApiServerVersionCheck();
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
p = inputParser;
p.addOptional('awg_sourcefile','', @ischar);
p.parse(varargin{:});

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% AWG %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Only used if this example is ran without the awg_sourcefile parameter:
% To ensure that we have a .seqc source file to use in this example, we
% write this to disk and then compile this file.
source_lines = {...
     '// Define an integer constant',...
     'const N = 4096;',...
     '// Create two Gaussian pulses with length N points,',...
     '// amplitude +1.0 (-1.0), center at N/2, and a width of N/8',...
     'wave gauss_pos = 1.0*gauss(N, N/2, N/8);',...
     'wave gauss_neg = -1.0*gauss(N, N/2, N/8);',...
     '// Continuous playback',...
     'while (true) {',...
     '  // Play pulse on AWG channel 1',...
     '  playWave(gauss_pos);',...
     '  // Wait until waveform playback has ended',...
     '  waitWave();',...
     '  // Play pulses simultaneously on both AWG channels',...
     '  playWave(gauss_pos, gauss_neg);',...
     '}'};
source = sprintf('%s\n',source_lines{:});
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Create an instance of the AWG Module
h = ziDAQ('awgModule');
ziDAQ('set', h, 'device', device);
ziDAQ('execute', h);
% Get the LabOne user data directory
data_dir = ziDAQ('getString', h, 'directory');
% The AWG Tab in the LabOne UI also uses this directory for AWG segc files.
src_dir = fullfile(data_dir, 'awg', 'src');
if ~(exist(src_dir,'dir') == 7)
    % The data directory is created by the AWG module and should always exist.
    % If this exception is raised, something might be wrong with the file system.
    ziDAQ('clear', h);
    error('AWG module src directory %s does not exist or is not a directory', src_dir);
end
% Note, the AWG source file must be located in the AWG source directory of the user's LabOne data directory.
if isempty(p.Results.awg_sourcefile)
    awg_sourcefile = 'ziDAQ_uhf_example_awg_sourcefile.seqc';
    fid = fopen(fullfile(src_dir, awg_sourcefile), 'wt');
    fprintf(fid, '%s', source);
    fclose(fid);
else
    awg_sourcefile = [p.Results.awg_sourcefile '.seqc'];
    if ~(exist(fullfile(src_dir, awg_sourcefile), 'file') == 2)
        ziDAQ('clear', h);
        error('The file %s does not exist in directory %s.', awg_sourcefile, src_dir);
    end
end
fprintf('Will compile and load %s, from %s.\n', awg_sourcefile, src_dir);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Note: when using an AWG program from a source file (and only then), the compiler needs to
% be started explicitly with awgModule.set('compiler/start', 1)
ziDAQ('set', h, 'compiler/sourcefile', awg_sourcefile);
ziDAQ('set', h, 'compiler/start', 1);
% Wait for compilation
while ziDAQ('getInt', h, 'compiler/status') == -1
    pause(0.1);
end

% Check the statuse of compilation
compilerStatus = ziDAQ('getInt', h, 'compiler/status');
compilerString = ziDAQ('getString', h, 'compiler/statusstring');
if compilerStatus == 1
    % Compilation failed, send an error message
    ziDAQ('clear', h);
    error(char(compilerString))
else
    if compilerStatus == 0
        disp('Compilation successful with no warnings, will upload the program to the instrument.');
    end
    if compilerStatus == 2
        disp('Compilation successful with warnings, will upload the program to the instrument.');
        disp(['Compiler warning: ' char(compilerString)]);
    end
    % Wait for waveform upload to finish
    k = 0;
    while ziDAQ('getDouble', h, 'progress') < 1
        fprintf('%d progress: %.1f%%.\n', k, ziDAQ('getDouble', h, 'progress'));
        pause(0.1);
        k = k + 1;
    end
    fprintf('%d progress: %.1f%%.\n', k, 100*ziDAQ('getDouble', h, 'progress'));
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
% Start the AWG in continuous mode
disp('Enabling the AWG');
% Preferred method of using the AWG: Run in single mode, continuous
% waveform playback is best achieved by using an infinite loop (e.g.,
% while (true)) in the sequencer program.
ziDAQ('setInt', ['/' device '/awgs/0/single'], 1);
ziDAQ('setInt', ['/' device '/awgs/0/enable'], 1);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);
end
