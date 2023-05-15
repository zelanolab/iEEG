#!/usr/bin/env bash
#
# skull-strip using SPM's segmentation tool
#
# Usage
#   ./SkullStrip_SPM.sh full-path-to-image
# only .nii and .nii.gz format are accepted
#   

# One input argument is required
if [[ $# -ne 1 ]]; then
	printf "Incorrect input argumetns.\n Usage: ./SkullStrip_SPM.sh full-path-to-nifiti-image\n"
	exit 1;
fi

## only .nii & .nii.gz
img=$1

# folder name sufix to save SPM segment results
segname=SPMSegment

# make sure input file exists
[ -f ${img} ] || { printf "File doest not eist: ${img}\n"; exit 1; }

# Use spm to do skull stripping
job_template='${script_dir}/spm_segment_job.mat'
#[ -f ${job_template} ] || { printf "SPM job template %s does not exist\n" ${job_template}; exit 1; }

# Retrieve script directory
current_dir=$(pwd)
script_dir=$(dirname '$0')
if [ '$script_dir' = '.' ] ; then
   script_dir="$current_dir"
fi
printf "Script directory: %s\n" $script_dir

subjdir=$(dirname "$img")
filename=$(basename "$img")
ext="${filename##*.}"
fname="${filename%.*}"
segdir=${subjdir}/${segname}
[ -d ${segdir} ] || mkdir ${segdir}

if [[ ${ext} == "gz" ]]; then
    gunzip -c ${img} > ${segdir}/${fname}
    file2seg=${segdir}/${fname}
    anat=${fname}
    
else
    cp ${img} ${segdir}
    file2seg=${segdir}/${filename}
    anat=${filename}
fi

ls ${segdir}/c*${anat} 2>/dev/null
# run SPM segmentation if no tissue files were found
if [[ $? -ne 0 ]]; then
    printf "SPM brain segmentation for %s \n\n\n\n" ${file2seg}
    #matlab -nojvm -nodesktop -nosplash -r "spm_segment_job( '${file2seg}', '${job_template}'); exit";
    # spm_segment_job.m is in the same directory of this script
    current_dir=$(pwd)
    matlab -nojvm -nodesktop -nosplash -r "addpath( '${current_dir}'); spm_segment_job( '${file2seg}'); exit";
fi

# retrieve brain from segment tissues
if [ -f ${segdir}/c1${anat} ] && [ -f ${segdir}/c2${anat} ] && [ -f ${segdir}/c3${anat} ] && [ -f ${segdir}/c4${anat} ] ; then
    # CSF mask
    #printf "Thresholding CSF mask at %s \n" ${csf_threshold}
    #fslmaths ${segdir}/c3${anat}.nii -uthr ${csf_threshold} -bin ${segdir}/csf_${csf_threshold}    
    filename=$(basename "$anat")
    anat="${filename%.*}"
    
    # retrieve brain
    printf "Extracted brain gray + white + csf \n"
    fslmaths ${segdir}/c3${anat} -uthr 0.9 -add ${segdir}/c1${anat} -add ${segdir}/c2${anat} -bin -mul ${subjdir}/${anat} ${subjdir}/${anat}_brain -odt float
    fslmaths ${subjdir}/${anat}_brain ${segdir}/raw_${anat}_brain
    fslmaths ${segdir}/c1${anat} -add ${segdir}/c2${anat} -bin -mul ${subjdir}/${anat} ${segdir}/${anat}_greywhiteMatter -odt float

    # fill holes
    c=($(fslstats ${subjdir}/${anat}_brain  -C))
    cx=$( printf "%.0f" ${c[0]})
    cy=$( printf "%.0f" ${c[1]})
    cz=$( printf "%.0f" ${c[2]})
    bet ${subjdir}/${anat}_brain ${subjdir}/${anat}_brain -f 0.005 -g 0 -n -m -c $cx $cy $cz
    fslmaths ${subjdir}/${anat}_brain_mask -mul ${subjdir}/${anat} ${subjdir}/${anat}_brain
    
    printf "Thresholding skull mask at 0.99 \n" 
    fslmaths ${segdir}/c4${anat} -thr 0.99 -bin ${segdir}/c4${anat}_bin
    
    # retrieve in-brain
    fslmaths ${segdir}/c1${anat} -add ${segdir}/c2${anat} -add ${segdir}/c3${anat} -bin -add ${segdir}/c4${anat}_bin -mul ${subjdir}/${anat} ${segdir}/${anat}_inskull -odt float
    bet ${segdir}/${anat}_inskull ${segdir}/${anat}_inskull -f 0.0001 -g 0 -n -m
    
else
    printf "Segmentation files in directory %s are not complete. Delete old files and re-try.\n " ${segdir}
fi
