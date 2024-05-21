#!/usr/bin/env bash
#
# Register post-operative CT to standard MNI brain
#
# Brain images: CT.nii.gz | MR_pre.nii.gz | MR_after.nii.gz
#
#   Field-bias correction and skull stripping are skipped by default.
#   So make sure MR_pre_brain.nii.gz and/or MR_after_brain.nii.gz exist
#   or, set do_fb=0 and do_skuppstrip=0 to run skull stripping
# 
# Software packages: FSL & Matlab toolbox SPM12 (for skull-stripping)
#
# Resulting folder: reg
#   ct -> post-plant -> pre-plant -> standard
#   ct -> post-plant -> standard
#   ct -> pre-plant -> standard
#   ct -> standard
# 
# Usage
#   cd '${scriptdir}'
#   ./RegCT2STD.sh full-subject-directory
#
# skull-stripping requires the following scripts:
# 	SkullStrip_SPM.sh spm_segment_job.m
#
# naturalzhou@gmail.com
# Zelano Lab@Northwestern University
#
# Feb 16, 2023, add orientation check
# Oct 10, 2022
# September 23, 2019


# full path to subejct's brain image folder
subjdir=$1

# field-bias correction, 1-no; 0-yes
do_fb=0

# skull stripping, 1-do not run; 0-run skull stripping
do_skuppstrip=0

# Overwrite previous sgemantation and registeration results; 1-no; 0-yes
re_run=0

# Register individual MR to standard MNI152 brain
std=${FSLDIR}/data/standard/MNI152_T1_1mm_brain

##************************************************************************
# File names of the images (without extensions).
# Fll images must be in compressed nifti format (.nii.gz)
anat_pre=MR_pre
anat_after=MR_after
ct=CT
## End of parameters setup
###############################################

if [ "$#" -ne 1 ] || ! [ -d "$1" ]; then
  printf "Usage: $0 full-path-to-subject" >&2
  exit 1
fi

# Make sure fsl is isntalled
[ "${FSLDIR}" == "" ] && { printf "FSL has not been installed.\n"; exit 1; }
command -v fsleyes &> /dev/null
[ $? -ne 0 ] && export PATH=$PATH:${FSLDIR}/bin

# make sure the subject directory exists
# Remove the file separator appearing at the end
d=$( dirname ${subjdir})
n=$( basename ${subjdir})
subjdir=${d}/${n}

if [[ -d "${subjdir}" ]]; then
    printf "Working directory: %s.\n" ${subjdir}
else
    printf "%s does not exist. \n"  ${subjdir}
    exit 1;
fi

# at least one of the three images must exist
f_pre=${subjdir}/${anat_pre}.nii.gz
f_after=${subjdir}/${anat_after}.nii.gz
f_ct=${subjdir}/${ct}.nii.gz
if [[ ! -f ${f_pre} && ! -f ${f_after} && ! -f ${f_ct} ]]; then
    printf "**None of the following images were found:\n  %s\n  %s\n  %s\n" ${f_pre} ${f_after} ${f_ct}
    exit 1
fi

# Check orientation if Freesufer's mri_info is available
if [[ -x "$(command -v mri_info)" ]] ; then
    pre_orient=""
    after_orient=""
    ct_orient=""
    orient_err=0
    if [[ -f ${f_pre} ]]; then
        pre_orient=$(mri_info ${f_pre} | grep "Orientation" | cut -d ":" -f2 | xargs)
    fi

    if [[ -f ${f_after} ]]; then
        after_orient=$(mri_info ${f_after} | grep "Orientation" | cut -d ":" -f2 | xargs)
    fi

    if [[ -f ${f_ct} ]]; then
        ct_orient=$(mri_info ${f_ct} | grep "Orientation" | cut -d ":" -f2 | xargs)
    fi

    s=" "
    [ "${pre_orient}" != "" ] && [[ "${pre_orient}" != "LAS" && "${pre_orient}" != "RAS" ]] && { s="${s} ${anat_pre}"; orient_err=1; }
    [ "${after_orient}" != "" ] && [[ "${after_orient}" != "LAS" && "${after_orient}" != "RAS" ]] && { s="${s} ${anat_after}"; orient_err=1; }
    [ "${ct_orient}" != "" ] && [[ "${ct_orient}" != "LAS"  && "${ct_orient}" != "RAS" ]] && { s="${s} ${ct}"; orient_err=1; }

    if [[ ${orient_err} == 1 ]]; then
        printf "Error: Orientation of %s is not a standard orientation.\n" $s
        printf "Error: Reorient the images to match the orientation of the standard template images (MNI152) (see fslreorient2std)\n"
        exit 1;
    fi
fi


current_dir=$(pwd)
scriptdir=$(dirname "$0")
[ "${scriptdir}" == "." ] && scriptdir="$current_dir"

printf "Script directory: %s\n" ${scriptdir}
printf "Over-write existing files (1-no; 0-yes): %d\n" ${re_run}
printf "Standard brain: %s\n" ${std}

##********************************************************
## Field-bias correction
if [[ ${do_fb} -eq 0 ]]; then
    fbdir=${subjdir}/FieldBiasCorr
    [ -d ${fbdir} ] || mkdir -p ${fbdir}

    for vol in ${anat_pre} ${anat_after}; do
        ivol=${subjdir}/${vol}.nii.gz
        ovol=${subjdir}/orig_${vol}.nii.gz

        [ -f ${ivol} ] || continue

        printf "Field bias correction for: %s\n" ${ovol}
        # Make a copy of the original image
        [ -f ${ovol} ] || fslmaths ${ivol} ${ovol}
        fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -g -B -o ${fbdir}/fb_${vol} ${ovol}
        fslmaths ${fbdir}/fb_${vol}_restore ${ivol}
    done
fi
############################################################################################

##********************************************************************************************
# Skull-stripping
if [[ ${do_skuppstrip} -eq 0 ]]; then
    f=${scriptdir}/SkullStrip_SPM.sh
    [ -f ${f} ] || { printf "**SkullStrip_SPM.sh was not found.\n"; exit 1; }
    f=${scriptdir}/spm_segment_job.m
    [ -f ${f} ] || { printf "**spm_segment_job.m was not found.\n"; exit 1; }
	
    printf "Skull-stripping ...\n"
    for mr in ${anat_pre} ${anat_after}; do
        # Resulting files:${mr}_brain SPMSegment/${mr}_inskull_mask SPMSegment/c*
        f_mr=${subjdir}/${mr}.nii.gz
        [ -f ${f_mr} ] || continue

        seg_dir=${subjdir}/SPMSegment

        # check if the segmentation has already been done
        mr_brain=${subjdir}/${mr}_brain.nii.gz
        if [[ -d ${seg_dir} && ${re_run} -eq 1 && -f ${mr_brain} ]]; then
            printf "    %s has been run, skipped. \n" ${f_mr}
        else
            printf "    %s\n" ${f_mr}
            "${scriptdir}/SkullStrip_SPM.sh" ${f_mr}
            [ $? -ne 0 ] && { printf "**Failed to run skull-stripping using SPM."; exit 1; }
        fi
    done
fi # End of skull-stripping
######################################################################

##********************************************************************************************
# Registration
printf "\n\nMR images registration\n"
regdir=${subjdir}/reg
rlog=${regdir}/reglog.txt
[ -d ${regdir} ] || { printf "  Registeration directory: %s\n" ${regdir}; mkdir -p ${regdir}; }
touch ${rlog}

# Register Pre-operation MR to standard brain
pre_brain=${subjdir}/${anat_pre}_brain.nii.gz
pre_mat=${regdir}/${anat_pre}2std.mat
inv_pre_mat=${regdir}/inv_${anat_pre}2std.mat
[[ -f ${pre_mat} && ${re_run} -eq 1 ]] && rereg_pre=1 || rereg_pre=0
if [[ -f ${pre_brain} && ${rereg_pre} -eq 1 ]]; then
    printf "    %s has already been registered to %s\n" ${pre_brain} ${std}
fi

if [[ -f ${pre_brain} && ${rereg_pre} -eq 0 ]]; then
    printf "    Registering %s to %s\n" ${pre_brain} ${std} >> ${rlog}
    oimg=${regdir}/${anat_pre}_brain2std
    printf "flirt -ref ${std} -in ${pre_brain} -omat ${pre_mat} -out ${oimg} \n" >> ${rlog}
    flirt -ref ${std} -in ${pre_brain} -omat ${pre_mat} -out ${oimg}
    convert_xfm -omat ${inv_pre_mat} -inverse ${pre_mat}
fi

# Register post-operation MR to standard brain; MR_after -> MR_pre -> standard
post_brain=${subjdir}/${anat_after}_brain.nii.gz
post_mat=${regdir}/${anat_after}2std.mat
inv_post_mat=${regdir}/inv_${anat_after}2std.mat
[[ -f ${post_mat} && ${re_run} -eq 1 ]] && rereg_post=1 || rereg_post=0
if [[ -f ${post_brain} && ${rerun_post} -eq 1 ]]; then
    printf "    %s has already been registered to %s\n" ${post_brain} ${std}
fi

if [[ -f ${post_brain} && ${rerun_post} -eq 0 ]]; then
    oimg=${regdir}/${anat_after}_brain2std
    in_transf=${regdir}/${anat_after}2${anat_pre}.mat
    in_oimg=${regdir}/${anat_after}2${anat_pre}
    if [[ -f ${pre_brain} ]]; then
        # post-operation MR -> pre-operation MR
        printf "    Registering %s to %s\n" ${post_brain} ${pre_brain} >> ${rlog}
        printf "flirt  -in ${post_brain} -ref ${pre_brain} -dof 7 -omat ${in_transf} -out ${in_oimg} \n" >> ${rlog}
        flirt  -in ${post_brain} -ref ${pre_brain} -dof 7 -omat ${in_transf} -out ${in_oimg}

        # combine post->pre and pre->standard
        convert_xfm -omat ${post_mat} -concat ${pre_mat} ${in_transf}
        printf "flirt -in ${post_brain} -ref ${std} -applyxfm -init ${post_mat} -out ${oimg} \n" >> ${rlog}
        flirt -in ${post_brain} -ref ${std} -applyxfm -init ${post_mat} -out ${oimg}

    else
        # register after to standard directly
        printf "flirt -ref ${std} -in ${post_brain} -omat ${post_mat} -out ${oimg} \n" >> ${rlog}
        flirt -ref ${std} -in ${post_brain} -omat ${post_mat} -out ${oimg}
    fi

    convert_xfm -omat ${inv_post_mat} -inverse ${post_mat}
fi # MR_after exist
##############################################################################################

# Register CT image to MR image
printf "\n\nRegistration of CT image\n"
ct_mask=${subjdir}/${ct}_brainmask

# No CT, exit without error
[ -f ${f_ct} ] || exit 0

# The registration has been run
if [[ -f ${regdir}/ct2std.mat && ${re_run} -eq 1 ]]; then
    printf "    CT image has already been registered to the standard brain, skipped.\n"
    exit 0
fi

if [[ -f ${f_pre} && -f ${f_after} ]]; then
    # Both pre- and post-MRI exist
    mr=${anat_after}
    ref=${subjdir}/${mr}
    init_nam=${regdir}/ct2${mr}_init
    init_mat=${init_nam}.mat
    aff_nam=${regdir}/ct2${mr}_affine
    aff_mat=${aff_nam}.mat

    # inital 6-degree linear transformation: CT -> postMR
    printf "#Initial registeration from %s to %s using mutalinfo as cost function.\n" ${f_ct} ${ref} >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam} \n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -searchcost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam}

    # affine transformation: CT -> postMR
    printf "#Affine registeration from %s to %s using mutalinfo as cost function.\n" ${f_ct} ${ref} >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}

    # clean up
    [ -f ${init_mat} ] && rm ${init_mat}

    # CT -> postMR -> preMR -> MNI152
    ct2pre_nam=${regdir}/ct2${mr}2${anat_pre}
    ct2pre_mat=${ct2pre_nam}.mat
    inv_ct2pre_mat=${regdir}/inv_ct2${mr}2${anat_pre}.mat
    ct2std_nam=${regdir}/ct2${mr}2${anat_pre}2std
    ct2std_mat=${ct2std_nam}.mat
    inv_ct2std_mat=${regdir}/inv_ct2${mr}2${anat_pre}2std.mat
    post2pre_mat=${regdir}/${mr}2${anat_pre}.mat

    convert_xfm -omat ${ct2pre_mat} -concat ${post2pre_mat} ${aff_mat}
    convert_xfm -omat ${ct2std_mat} -concat ${pre_mat} ${ct2pre_mat}
    convert_xfm -omat ${inv_ct2std_mat} -inverse ${ct2std_mat}
    convert_xfm -omat ${inv_ct2pre_mat} -inverse ${ct2pre_mat}

    cp ${ct2std_mat} ${regdir}/ct2std.mat
    cp ${inv_ct2std_mat} ${regdir}/inv_ct2std.mat

    printf "#Register %s to standard brain %s.\n" ${f_ct} ${std} >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${std} -applyxfm -init ${ct2std_mat} -out ${ct2std_nam} \n" >> ${rlog}
    flirt -in ${f_ct} -ref ${std} -applyxfm -init ${ct2std_mat} -out ${ct2std_nam}

    printf "flirt -in ${aff_nam} -ref ${f_pre} -applyxfm -init ${post2pre_mat} -out ${ct2pre_nam} \n" >> ${rlog}
    flirt -in ${aff_nam} -ref ${f_pre} -applyxfm -init ${post2pre_mat} -out ${ct2pre_nam}
            
    # brain mask in CT space
    mr_mask=${subjdir}/${anat_pre}_brain_mask.nii.gz
    if [[ ! -f ${mr_mask} ]]; then
        fslmaths ${pre_brain} -bin -fillh -bin ${mr_mask}        
    fi

    flirt -in ${mr_mask} -ref ${f_ct} -applyxfm -init ${inv_ct2pre_mat} -out ${ct_mask}
    fslmaths ${ct_mask} -bin ${ct_mask}

elif [[ -f ${f_pre} || -f ${f_after} ]]; then
    # One of MR_pre and MR_after exist
    [ -f ${f_pre} ] && mr=${anat_pre} || mr=${anat_after}

    ref=${subjdir}/${mr}
    init_nam=${regdir}/ct2${mr}_init
    init_mat=${init_nam}.mat
    aff_nam=${regdir}/ct2${mr}_affine
    aff_mat=${aff_nam}.mat
    inv_aff_mat=${regdir}/inv_ct2${mr}_affine.mat

    # Inital 6-degree linear transformation: CT->MR
    printf "#Initial registeration using mutalinfo as cost function.\n" >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -searchcost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -searchcost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam}

    # Affine transformation: CT->MR
    printf "#Affine registeration using mutalinfo as cost function.\n" >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -searchcost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -searchcost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}

    [ -f ${init_mat} ] && rm ${init_mat}
    convert_xfm -omat ${inv_aff_mat} -inverse ${aff_mat}

    # CT->MNI152
    ct2std_nam=${regdir}/ct2${mr}2std
    ct2std_mat=${ct2std_nam}.mat
    inv_ct2std_mat=${regdir}/inv_ct2${mr}2std.mat
    mr2std_mat=${regdir}/${mr}2std.mat

    printf "#Register %s to standard brain %s.\n" ${f_ct} ${std} >> ${rlog}
    printf "flirt -in ${aff_nam} -ref ${std} -applyxfm -init ${mr2std_mat} -out ${ct2std_nam}\n" >> ${rlog}
    flirt -in ${aff_nam} -ref ${std} -applyxfm -init ${mr2std_mat} -out ${ct2std_nam}

    # concatenate transformation matrix
    printf "#Concatenate transformation matrix ${mr2std_mat} & ${aff_mat}\n" >> ${rlog}
    printf "convert_xfm -omat ${ct2std_mat} -concat ${mr2std_mat} ${aff_mat}\n" >> ${rlog}
    convert_xfm -omat ${ct2std_mat} -concat ${mr2std_mat} ${aff_mat}

    printf "#Inverse transformation matrix from standard space to CT space\n" >> ${rlog}
    printf "convert_xfm -omat ${inv_ct2std_mat} -inverse ${ct2std_mat}\n" >> ${rlog}
    convert_xfm -omat ${inv_ct2std_mat} -inverse ${ct2std_mat}

    cp ${ct2std_mat} ${regdir}/ct2std.mat
    cp ${inv_ct2std_mat} ${regdir}/inv_ct2std.mat

    # brain mask in CT space
    mr_mask=${subjdir}/${mr}_brain_mask.nii.gz
    if [[ ! -f ${mr_mask} ]]; then
        fslmaths ${subjdir}/${mr}_brain -bin -fillh -bin ${mr_mask}        
    fi

    flirt -in ${mr_mask} -ref ${f_ct} -applyxfm -init ${inv_aff_mat} -out ${ct_mask}
    fslmaths ${ct_mask} -bin ${ct_mask}

else # Only CT was available
    if [[ -f ${ct2std}  && ${re_run} -eq 1 ]]; then
        printf "    CT image has already been registered to the standard brain, which may not be accurate.\n"
    else
        mat=${regdir}/ct2std.mat
        inv_mat=${regdir}/inv_ct2std.mat

        printf "#Registering CT image to directly to the standard brain, this may not be accurate.\n" >> ${rlog}
        printf "flirt -in ${f_ct} -ref ${std} -dof 12 -cost mutualinfo -searchcost mutualinfo -omat ${mat} -out ${ct2std}\n" >> ${rlog}
        flirt -in ${f_ct} -ref ${std} -dof 12 -cost mutualinfo -searchcost mutualinfo -omat ${mat} -out ${ct2std}

        printf "#Inverse transformation matrix from standard space to CT space\n" >> ${rlog}
        printf "convert_xfm -omat ${inv_mat} -inverse ${mat}\n" >> ${rlog}
        convert_xfm -omat ${inv_mat} -inverse ${mat}

        flirt -in ${std}_mask -ref ${f_ct} -applyxfm -init ${inv_mat} -out ${ct_mask}
    fi
fi

# End of Register CT image to MR image
##############################################################################################
