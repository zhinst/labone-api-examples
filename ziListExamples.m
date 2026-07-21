function ziListExamples
% ZILISTEXAMPLES lists all available examples in the api-examples project
%
% USAGE:
% ziListExamples();

mfile = which(mfilename);
[pathstr, ~] = fileparts(mfile);

examples = dir([pathstr filesep '**/*example_*.m']);

for example = examples.'
    disp(example.name)
end
end
