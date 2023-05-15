function [tissues] = spm_segment_job( vol, job_template, varargin)
% Run brain segmentation using SPM12
% 
% Usage
%   spm_segment_job( vol, job_template)
% 
% Input
%   vol, full_path_to_file path/vol.nii
%   job_template, '' | full-path-to a job template file
% 
% Output
%   tissues, 5 x1 cell array of full path to tissue files
%           */c1*.nii (gray matter) */c2*.nii (white matter) */c3*.nii (CSF) */c4*.nii */c5*.nii
% 

if exist( 'job_template', 'var') && exist( job_template, 'file')
    job = load( job_template);
    job = job.job;

else
    job =[];
    job.channel.biasfwhm = 60;
    job.channel.biasreg = 0.001;
    job.channel.write = [0, 0];

    job.warp.affreg = 'mni';
    job.warp.cleanup = 1;
    job.warp.fwhm = 0;
    job.warp.mrf = 1;
    job.warp.reg = [0, 0.001, 0.5, 0.05, 0.2];
    job.warp.samp = 3;
    job.warp.write = [0, 0];

    job.tissue(1).ngaus = 1;
    job.tissue(1).native = [1, 0];
    job.tissue(1).warped = [0, 0];

    job.tissue(2).ngaus = 1;
    job.tissue(2).native = [1, 0];
    job.tissue(2).warped = [0, 0];
    
    job.tissue(3).ngaus = 2;
    job.tissue(3).native = [1, 0];
    job.tissue(3).warped = [0, 0];

    job.tissue(4).ngaus = 3;
    job.tissue(4).native = [1, 0];
    job.tissue(4).warped = [0, 0];

    job.tissue(5).ngaus = 4;
    job.tissue(5).native = [1, 0];
    job.tissue(5).warped = [0, 0];

    job.tissue(6).ngaus = 2;
    job.tissue(6).native = [0, 0];
    job.tissue(6).warped = [0, 0];
end

job.channel.vols = {vol};
spmdir = which( 'spm');
if isempty( spmdir)
    error( 'SPM toolbox was not found.');
end

spmdir = fileparts( spmdir);
tissue_prior = fullfile( fullfile( spmdir, 'tpm'), 'TPM.nii');
for k = 1 : 6
    job.tissue(k).tpm = [tissue_prior, ',', num2str( k)];
end

try
    spm_preproc_run( job);
    [wkpath, volname, ext] = fileparts( vol);
    tissues = cell( 5, 1);
    for k = 1 : 5
        tissues{ k, 1} = fullfile( wkpath, ['c', num2str(k), volname, ext]);
    end
    
catch
    tissue = {};
    fprintf( 'Something went wrong during running SPM segmentation.');
end

end %  function