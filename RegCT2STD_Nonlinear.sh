#!/usr/bin/env bash
#
## ** TODO
#
# Register post-operative CT to standard MNI brain
#
# Brain images: CT.nii.gz and MR_pre.nii.gz and/or MR_after.nii.gz
#
# Field-bias correction and skull stripping are skipped by default.
# So make sure MR_pre_brain and/or MR_after_brain exist
# or, set do_fb=0 and do_skuppstrip=0 to run skull stripping
# 
# Software packages: FSL & Matlab toolbox SPM12 (for skull-stripping)
#
# Resulting folder: reg
#   ct -> post-operation-> pre-operation -> MNI
#   ct -> post-operation -> MNI
#   ct -> pre-operation -> MNI
#   ct -> MNI
# 
# Usage
#   RegCT2STD_Nonlinear.sh full-path-to-subject-folder
#
# Skull-stripping requires the following scripts:
# 	SkullStrip_SPM.sh spm_segment_job.m
#
# Steps of nonlinear registration of T1 to MNI
# Linear registration from T1 to standard
# flirt -ref ${std} -in ${t1brain} -omat t12std_affine_transf.mat
# Nonlinear registration from T1 to standard
# fnirt --in=${t1} --aff=t12std_affine_transf.mat --cout=t12std_nonlinear_transf --config=T1_2_MNI152_2mm
# Combine linear and non-linear
# applywarp --ref=${std} --in=${t1brain} --warp=t12std_nonlinear_transf --out=warped_${t1brain}
# Inverse registration
# invwarp --ref=${t1brain} --warp=t12std_nonlinear_transf --out=std2t1_nonlinear_transf
#
#
# naturalzhou@gmail.com
# Zelano Lab@Northwestern University
#
# Revision history
#   March 29, 2024: add nonliear registration option (GZ)
#   Feburary 16, 2023: add orientation check (GZ)
#   October 10, 2022:
#   September 23, 2019:

###### Parameters setup ######
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

# File names (without extensions). Must be compressed nifti format (.nii.gz)
anat_pre=MR_pre
anat_after=MR_after
ct=CT
###### End of parameters setup ######

# One input argument required
if [ "$#" -ne 1 ] || ! [ -d "$1" ]; then
  printf "Usage: $0 full-path-to-subject\n" >&2
  exit 1
fi

# Make sure the subject directory exists
# Remove the file separator appearing at the end if necessary
d=$( dirname ${subjdir})
n=$( basename ${subjdir})
subjdir=${d}/${n}
[ -d "${subjdir}" ] || { printf "Error: directory not found: %s.\n" ${subjdir}; exit 1; }

# Make sure FSL is isntalled
[ "${FSLDIR}" == "" ] && { printf "FSL has not been installed.\n"; exit 1; }
command -v fsleyes &> /dev/null
[ $? -ne 0 ] && export PATH=$PATH:${FSLDIR}/bin

# registration folder and log file
regdir=${subjdir}/reg
rlog=${regdir}/reglog.txt
[ -d "${regdir}" ] || mkdir -p ${regdir}
[ -f "${rlog}" ] || touch ${rlog}
printf "Registeration directory: %s\nLog file: %s\n" ${regdir} ${rlog}

# at least one of the three images must exist
f_pre=${subjdir}/${anat_pre}.nii.gz
f_after=${subjdir}/${anat_after}.nii.gz
f_ct=${subjdir}/${ct}.nii.gz
if [[ ! -f ${f_pre} && ! -f ${f_after} && ! -f ${f_ct} ]]; then
    printf "#Error: None of the following images were found:\n%s\n%s\n%s\n" ${f_pre} ${f_after} ${f_ct} >> ${rlog}
    exit 1
fi

# Check orientation if Freesufer's mri_info is available
ori_err=0
if [[ -x "$(command -v mri_info)" ]] ; then
    pre_ori=""
    after_ori=""
    ct_ori=""
    if [[ -f ${f_pre} ]]; then
        pre_ori="$(mri_info ${f_pre} | grep "Orientation" | cut -d ":" -f2 | xargs)"
    fi

    if [[ -f ${f_after} ]]; then
        after_ori="$(mri_info ${f_after} | grep "Orientation" | cut -d ":" -f2 | xargs)"
    fi

    if [[ -f ${f_ct} ]]; then
        ct_ori="$(mri_info ${f_ct} | grep "Orientation" | cut -d ":" -f2 | xargs)"
    fi

    s=" "
    if [[ ${pre_ori} != "" ]]; then
        [[ ${pre_ori} != "LAS" && ${pre_ori} != "RAS" ]] && { s="${s} ${anat_pre}"; ori_err=1; }
    fi

    if [[ ${after_ori} != "" ]]; then
        [[ ${after_ori} != "LAS" && ${after_ori} != "RAS" ]] && { s="${s} ${anat_after}"; ori_err=1; }
    fi

    if [[ ${ct_ori} != "" ]]; then
        [[ ${ct_ori} != "LAS"  && ${ct_ori} != "RAS" ]] && { s="${s} ${ct}"; ori_err=1; }
    fi

else
    printf "# Failed to check the orientation of input images because mri_info was not available.\n" >> ${rlog}
fi

if [[ ${ori_err} == 1 ]]; then
    printf "# Error: Orientation of %s is not a standard orientation.\n" "${s}" >> ${rlog}
    printf "#    Reorient the images to match the orientation of the standard brain.\n" >> ${rlog}
    exit 1;
fi

current_dir="$(pwd)"
scriptdir="$(dirname "$0")"
[ "${scriptdir}" == "." ] && scriptdir="${current_dir}"
printf "\n\n\n# *********Job started at %s*********\n\n\
# Script directory: %s\n\
# Standard brain: %s\n\
# Run filed-bias correction (1-no; 0-yes): %d\n\
# Run skull-stripping (1-no; 0-yes): %d\n\
# Over-write existing files (1-no; 0-yes): %d\n" \
$(date +%Y-%m-%d_%H:%M:%S) ${scriptdir} ${std} ${do_db} ${do_skuppstrip} ${re_run} >> ${rlog}

# It seems not be working
set -o history
set -o histexpand

# Field-bias correction directory
fbdir=${subjdir}/FieldBiasCorr
# SPM segmentation directory
seg_dir=${subjdir}/SPMSegment

###### Field-bias correction ######
if [[ ${do_fb} -eq 0 ]]; then
    [ -d ${fbdir} ] || mkdir -p ${fbdir}

    for vol in ${anat_pre} ${anat_after}; do
        ivol=${subjdir}/${vol}.nii.gz
        [ -f "${ivol}" ] || continue

        # Make a copy of the original image
        ovol=${subjdir}/orig_${vol}.nii.gz
        if [[ ! -f "${ovol}" ]]; then
            printf "# Make a copy of original file.\n" >> ${rlog}
            printf "fslmaths ${ivol} ${ovol}\n" >> ${rlog}
            fslmaths ${ivol} ${ovol}
            # printf "!!\n" >> ${rlog}
        fi

        printf "# Field bias correction for: %s\n" ${ovol} >> ${rlog}
        printf "fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -g -B -o ${fbdir}/fb_${vol} ${ovol}\n" >> ${rlog}
        fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -g -B -o ${fbdir}/fb_${vol} ${ovol}
        # printf "!!\n" >> ${rlog}

        printf "fslmaths ${fbdir}/fb_${vol}_restore ${ivol}\n" >> ${rlog}
        fslmaths ${fbdir}/fb_${vol}_restore ${ivol}
        # printf "!!\n" >> ${rlog}
    done
fi
###### End of field-bias correction ######

###### Skull-stripping ######
if [[ ${do_skuppstrip} -eq 0 ]]; then
    ss_script=${scriptdir}/SkullStrip_SPM.sh
    [ -f ${ss_script} ] || { printf "# Error: SkullStrip_SPM.sh was not found.\n" >> ${rlog}; exit 1; }

    if [[ ! -f "${scriptdir}/spm_segment_job.m" ]]; then
        printf "# Error: **spm_segment_job.m was not found.\n" >> ${rlog}
        exit 1
    fi
	
    printf "#Skull-stripping ...\n"  >> ${rlog}
    for mr in ${anat_pre} ${anat_after}; do
        # Resulting files:${mr}_brain SPMSegment/${mr}_inskull_mask SPMSegment/c*
        f_mr=${subjdir}/${mr}.nii.gz
        [ -f ${f_mr} ] || continue

        # check if the segmentation has already been done
        mr_brain=${subjdir}/${mr}_brain.nii.gz
        if [[ -d "${seg_dir}" && ${re_run} -eq 1 && -f "${mr_brain}" ]]; then
            printf "# %s has been run, skipped. \n" ${f_mr} >> ${rlog}
            continue
        fi

        printf "# %s\n" ${f_mr} >> ${rlog}
        printf "${ss_script} ${f_mr}\n" >> ${rlog}
        "${ss_script}" ${f_mr}
        [ $? -ne 0 ] && { printf "# Skull-stripping failed.\n" >> ${rlog}; exit 1; }
    done
fi
###### End of skull-stripping ######


###### Registration of MRI images ######
printf "\n\n# Register MRI image to MNI template\n" >> ${rlog}

# Register Pre-operation MR to standard brain
pre_brain=${subjdir}/${anat_pre}_brain.nii.gz
pre_mat=${regdir}/${anat_pre}2std.mat
inv_pre_mat=${regdir}/inv_${anat_pre}2std.mat
pre_wrap=${regdir}/${anat_pre}2std_nonlinear_transf
inv_pre_wrap=${regdir}/inv_${anat_pre}2std_nonlinear_transf
[[ -f ${pre_mat} && ${re_run} -eq 1 ]] && rereg_pre=1 || rereg_pre=0
if [[ -f ${pre_brain} && ${rereg_pre} -eq 1 ]]; then
    printf "# %s has already been registered to %s\n" ${pre_brain} ${std} >> ${rlog}
fi

if [[ -f ${pre_brain} && ${rereg_pre} -eq 0 ]]; then
    printf "# Registering %s to %s\n" ${pre_brain} ${std} >> ${rlog}
    oimg=${regdir}/${anat_pre}_brain2std

    # Linear registration from T1 to MNI
    printf "flirt -ref ${std} -in ${pre_brain} -omat ${pre_mat} -out ${oimg}\n" >> ${rlog}
    flirt -ref ${std} -in ${pre_brain} -omat ${pre_mat} -out ${oimg}
    # printf "!!\n" >> ${rlog}

    printf "convert_xfm -omat ${inv_pre_mat} -inverse ${pre_mat}\n" >> ${rlog}
    convert_xfm -omat ${inv_pre_mat} -inverse ${pre_mat}
    # printf "!!\n" >> ${rlog}

    # non-linear registration from T1 to standard
    # fnirt --in=${pre_brain} --aff=${pre_mat} --cout=${pre_wrap} --config=T1_2_MNI152_2mm
    printf "fnirt --in=${f_pre} --aff=${pre_mat} --cout=${pre_wrap} --config=T1_2_MNI152_2mm\n" >> ${rlog}
    fnirt --in=${f_pre} --aff=${pre_mat} --cout=${pre_wrap} --config=T1_2_MNI152_2mm
    # printf "!!\n" >> ${rlog}

    printf "applywarp --ref=${std} --in=${pre_brain} --warp=${pre_wrap} --out=${regdir}/warped_${anat_pre}_brain\n" >> ${rlog}
    applywarp --ref=${std} --in=${pre_brain} --warp=${pre_wrap} --out=${regdir}/warped_${anat_pre}_brain
    # printf "!!\n" >> ${rlog}

    # invert warp from MNI to T1
    printf "invwarp --ref=${pre_brain} --warp=${pre_wrap} --out=${inv_pre_wrap}\n" >> ${rlog}
    invwarp --ref=${pre_brain} --warp=${pre_wrap} --out=${inv_pre_wrap}
    # printf "!!\n" >> ${rlog}
fi

# Register post-operation MR to standard brain; MR_after -> MR_pre -> standard
post_brain=${subjdir}/${anat_after}_brain.nii.gz
post_mat=${regdir}/${anat_after}2std.mat
inv_post_mat=${regdir}/inv_${anat_after}2std.mat
post_wrap=${regdir}/${anat_after}2std_nonlinear_transf
inv_post_wrap=${regdir}/inv_${anat_after}2std_nonlinear_transf
[[ -f ${post_mat} && ${re_run} -eq 1 ]] && rereg_post=1 || rereg_post=0
if [[ -f ${post_brain} && ${rerun_post} -eq 1 ]]; then
    printf "#    %s has already been registered to %s\n" ${post_brain} ${std} >> ${rlog}
fi

if [[ -f ${post_brain} && ${rerun_post} -eq 0 ]]; then
    oimg=${regdir}/${anat_after}_brain2std
    in_transf=${regdir}/${anat_after}2${anat_pre}.mat
    in_oimg=${regdir}/${anat_after}2${anat_pre}
    if [[ -f ${pre_brain} ]]; then
        # post-operation MR -> pre-operation MR
        printf "#    Registering %s to %s\n" ${post_brain} ${pre_brain} >> ${rlog}
        printf "flirt  -in ${post_brain} -ref ${pre_brain} -dof 7 -omat ${in_transf} -out ${in_oimg}\n" >> ${rlog}
        flirt  -in ${post_brain} -ref ${pre_brain} -dof 7 -omat ${in_transf} -out ${in_oimg}
        # printf "!!\n" >> ${rlog}

        # combine post->pre and pre->standard
        printf "convert_xfm -omat ${post_mat} -concat ${pre_mat} ${in_transf}\n" >> ${rlog}
        convert_xfm -omat ${post_mat} -concat ${pre_mat} ${in_transf}
        # printf "!!\n" >> ${rlog}

        printf "flirt -in ${post_brain} -ref ${std} -applyxfm -init ${post_mat} -out ${oimg}\n" >> ${rlog}
        flirt -in ${post_brain} -ref ${std} -applyxfm -init ${post_mat} -out ${oimg}
        # printf "!!\n" >> ${rlog}

    else
        # register after to standard directly
        printf "flirt -ref ${std} -in ${post_brain} -omat ${post_mat} -out ${oimg}\n" >> ${rlog}
        flirt -ref ${std} -in ${post_brain} -omat ${post_mat} -out ${oimg}
        # printf "!!\n" >> ${rlog}
    fi

    printf "convert_xfm -omat ${inv_post_mat} -inverse ${post_mat}\n" >> ${rlog}
    convert_xfm -omat ${inv_post_mat} -inverse ${post_mat}
    # printf "!!\n" >> ${rlog}

    # non-linear registration from T1 to standard
    #fnirt --in=${post_brain} --aff=${post_mat} --cout=${post_wrap} --config=T1_2_MNI152_2mm
    printf "fnirt --in=${f_post} --aff=${post_mat} --cout=${post_wrap} --config=T1_2_MNI152_2mm\n" >> ${rlog}
    fnirt --in=${f_post} --aff=${post_mat} --cout=${post_wrap} --config=T1_2_MNI152_2mm
    # printf "!!\n" >> ${rlog}

    printf "applywarp --ref=${std} --in=${post_brain} --warp=${post_wrap} --out=${regdir}/warped_${anat_after}_brain\n" >> ${rlog}
    applywarp --ref=${std} --in=${post_brain} --warp=${post_wrap} --out=${regdir}/warped_${anat_after}_brain
    # printf "!!\n" >> ${rlog}

    printf "invwarp --ref=${post_brain} --warp=${post_wrap} --out=${inv_post_wrap}\n" >> ${rlog}
    invwarp --ref=${post_brain} --warp=${post_wrap} --out=${inv_post_wrap}
    # printf "!!\n" >> ${rlog}
fi # MR_after exist
###### End of registration of MRI images ######


###### Registration of CT images ######
# No CT, exit without error
[ -f ${f_ct} ] || exit 0

ct_mask=${subjdir}/${ct}_brainmask
if [[ -f ${regdir}/ct2std.mat && ${re_run} -ne 0 ]]; then
    printf "# CT image has already been registered to the standard brain, skipped.\n" >> ${rlog}
    exit 0
else
    printf "\n\n# Register CT image to individual MRI and MNI template\n" >> ${rlog}
fi

# affine transformation matrix from CT to MNI
aff_ct2std=${regdir}/ct2std.mat
inv_aff_ct2std=${regdir}/inv_ct2std.mat
if [[ -f ${f_pre} && -f ${f_after} ]]; then
    # Both pre- and post-MRI exist
    mr=${anat_after}
    ref=${subjdir}/${mr}
    init_nam=${regdir}/ct2${mr}_init
    init_mat=${init_nam}.mat
    aff_nam=${regdir}/ct2${mr}_affine
    aff_mat=${aff_nam}.mat

    # inital 6-degree linear transformation: CT -> postMR
    printf "# Initial registeration from %s to %s using mutalinfo as cost function.\n" ${f_ct} ${ref} >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -searchcost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -searchcost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam}
    #printf "!!\n" >> ${rlog}

    # affine transformation: CT -> postMR
    printf "# Affine registeration from %s to %s using mutalinfo as cost function.\n" ${f_ct} ${ref} >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}
    # printf "!!\n" >> ${rlog}

    # clean up
    [ -f "${init_mat}" ] && rm ${init_mat}
    [ -f "${init_nam}.nii.gz" ] && rm ${init_nam}.nii.gz

    # CT -> postMR -> preMR -> MNI152
    ct2pre_nam=${regdir}/ct2${mr}2${anat_pre}
    ct2pre_mat=${ct2pre_nam}.mat
    inv_ct2pre_mat=${regdir}/inv_ct2${mr}2${anat_pre}.mat
    ct2std_nam=${regdir}/ct2${mr}2${anat_pre}2std
    ct2std_mat=${ct2std_nam}.mat
    inv_ct2std_mat=${regdir}/inv_ct2${mr}2${anat_pre}2std.mat
    post2pre_mat=${regdir}/${mr}2${anat_pre}.mat

    printf "convert_xfm -omat ${ct2pre_mat} -concat ${post2pre_mat} ${aff_mat}\n" >> ${rlog}
    convert_xfm -omat ${ct2pre_mat} -concat ${post2pre_mat} ${aff_mat}
    # printf "!!\n" >> ${rlog}

    printf "convert_xfm -omat ${ct2std_mat} -concat ${pre_mat} ${ct2pre_mat}\n" >> ${rlog}
    convert_xfm -omat ${ct2std_mat} -concat ${pre_mat} ${ct2pre_mat}
    # printf "!!\n" >> ${rlog}

    printf "convert_xfm -omat ${inv_ct2std_mat} -inverse ${ct2std_mat}\n" >> ${rlog}
    convert_xfm -omat ${inv_ct2std_mat} -inverse ${ct2std_mat}
    # printf "!!\n" >> ${rlog}

    printf "convert_xfm -omat ${inv_ct2pre_mat} -inverse ${ct2pre_mat}\n" >> ${rlog}
    convert_xfm -omat ${inv_ct2pre_mat} -inverse ${ct2pre_mat}
    # printf "!!\n" >> ${rlog}

    printf "cp ${ct2std_mat} ${aff_ct2std}\n" >> ${rlog}
    cp ${ct2std_mat} ${aff_ct2std}
    # printf "!!\n" >> ${rlog}

    printf "cp ${inv_ct2std_mat} ${inv_aff_ct2std}\n" >> ${rlog}
    cp ${inv_ct2std_mat} ${inv_aff_ct2std}
    # printf "!!\n" >> ${rlog}

    # Linear normalization CT->STD
    printf "# Register %s to standard brain %s.\n" ${f_ct} ${std} >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${std} -applyxfm -init ${ct2std_mat} -out ${ct2std_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${std} -applyxfm -init ${ct2std_mat} -out ${ct2std_nam}
    # printf "!!\n" >> ${rlog}

    printf "flirt -in ${aff_nam} -ref ${f_pre} -applyxfm -init ${post2pre_mat} -out ${ct2pre_nam}\n" >> ${rlog}
    flirt -in ${aff_nam} -ref ${f_pre} -applyxfm -init ${post2pre_mat} -out ${ct2pre_nam}
    # printf "!!\n" >> ${rlog}

    # Non-linear normalization CT->STD
    wrap_ct=${regdir}/warped_ct2std
    wrap_ct_transf=${regdir}/ct2${anat_pre}2std_nonlinear_transf
    inv_wrap_ct_transf=${regdir}/inv_ct2${anat_pre}2std_nonlinear_transf
    printf "applywarp --ref=${std} --in=${ct2pre_nam} --warp=${pre_wrap} --out=${wrap_ct}\n" >> ${rlog}
    applywarp --ref=${std} --in=${ct2pre_nam} --warp=${pre_wrap} --out=${wrap_ct}
    # printf "!!\n" >> ${rlog}

    printf "convertwarp --premat=${ct2pre_mat} --ref=${std} --warp1=${pre_wrap} --out=${wrap_ct_transf}\n" >> ${rlog}
    convertwarp --premat=${ct2pre_mat} --ref=${std} --warp1=${pre_wrap} --out=${wrap_ct_transf}
    # printf "!!\n" >> ${rlog}

    printf "applywarp --ref=${std} --in=${f_ct} --warp=${wrap_ct_transf} --out=${wrap_ct}2\n" >> ${rlog}
    applywarp --ref=${std} --in=${f_ct} --warp=${wrap_ct_transf} --out=${wrap_ct}2
    # printf "!!\n" >> ${rlog}

    printf "invwarp --ref=${f_ct} --warp=${wrap_ct_transf} --out=${inv_wrap_ct_transf}\n" >> ${rlog}
    invwarp --ref=${f_ct} --warp=${wrap_ct_transf} --out=${inv_wrap_ct_transf}
    # printf "!!\n" >> ${rlog}

    # brain mask in CT space
    mr_mask=${subjdir}/${anat_pre}_brain_mask.nii.gz
    if [[ ! -f "${mr_mask}" ]]; then
        printf "fslmaths ${pre_brain} -bin -fillh -bin ${mr_mask}\n" >> ${rlog}
        fslmaths ${pre_brain} -bin -fillh -bin ${mr_mask}
    fi

    printf "flirt -in ${mr_mask} -ref ${f_ct} -applyxfm -init ${inv_ct2pre_mat} -out ${ct_mask}\n" >> ${rlog}
    flirt -in ${mr_mask} -ref ${f_ct} -applyxfm -init ${inv_ct2pre_mat} -out ${ct_mask}
    # printf "!!\n" >> ${rlog}

elif [[ -f ${f_pre} || -f ${f_after} ]]; then
    mr=${anat_pre}
    mr_wrap=${pre_wrap}
    # Use MR_after if MR_pre does not exist
    [ -f ${f_pre} ] || { mr=${anat_after}; mr_wrap=${post_wrap}; }

    ref=${subjdir}/${mr}
    init_nam=${regdir}/ct2${mr}_init
    init_mat=${init_nam}.mat
    aff_nam=${regdir}/ct2${mr}_affine
    aff_mat=${aff_nam}.mat
    inv_aff_mat=${regdir}/inv_ct2${mr}_affine.mat

    # Inital 6-degree linear transformation: CT->MR
    printf "# Initial registeration using mutalinfo as cost function.\n" >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -searchcost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -cost mutualinfo -searchcost mutualinfo -dof 6 -omat ${init_mat} -out ${init_nam}
    # printf "!!\n" >> ${rlog}

    # Affine transformation: CT->MR
    printf "# Affine registeration using mutalinfo as cost function.\n" >> ${rlog}
    printf "flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -searchcost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}\n" >> ${rlog}
    flirt -in ${f_ct} -ref ${ref} -dof 12 -cost mutualinfo -searchcost mutualinfo -init ${init_mat} -omat ${aff_mat} -out ${aff_nam}
    # printf "!!\n" >> ${rlog}

    # clean up
    [ -f "${init_mat}" ] && rm ${init_mat}
    [ -f "${init_nam}.nii.gz" ] && rm ${init_nam}.nii.gz

    printf "convert_xfm -omat ${inv_aff_mat} -inverse ${aff_mat}\n" >> ${rlog}
    convert_xfm -omat ${inv_aff_mat} -inverse ${aff_mat}
    # printf "!!\n" >> ${rlog}

    # CT->MNI152
    ct2std_nam=${regdir}/ct2${mr}2std
    ct2std_mat=${ct2std_nam}.mat
    inv_ct2std_mat=${regdir}/inv_ct2${mr}2std.mat
    mr2std_mat=${regdir}/${mr}2std.mat

    printf "# Register %s to standard brain %s.\n" ${f_ct} ${std} >> ${rlog}
    printf "flirt -in ${aff_nam} -ref ${std} -applyxfm -init ${mr2std_mat} -out ${ct2std_nam}\n" >> ${rlog}
    flirt -in ${aff_nam} -ref ${std} -applyxfm -init ${mr2std_mat} -out ${ct2std_nam}
    # printf "!!\n" >> ${rlog}

    # apply warp to registered CT
    warp_ct=${regdir}/warped_ct2std
    warp_ct_transf=${regdir}/ct2${mr}2std_nonlinear_transf
    inv_warp_ct_transf=${regdir}/inv_ct2${mr}2std_nonlinear_transf
    printf "applywarp --ref=${std} --in=${aff_nam} --warp=${mr_wrap} --out=${warp_ct}\n" >> ${rlog}
    applywarp --ref=${std} --in=${aff_nam} --warp=${mr_wrap} --out=${warp_ct}
    # printf "!!\n" >> ${rlog}

    # apply warp to raw CT
    printf "convertwarp --premat=${aff_mat} --ref=${std} --warp1=${mr_wrap} --out=${warp_ct_transf}\n" >> ${rlog}
    convertwarp --premat=${aff_mat} --ref=${std} --warp1=${mr_wrap} --out=${warp_ct_transf}
    # printf "!!\n" >> ${rlog}

    printf "applywarp --ref=${std} --in=${f_ct} --warp=${warp_ct_transf} --out=${warp_ct}2\n" >> ${rlog}
    applywarp --ref=${std} --in=${f_ct} --warp=${warp_ct_transf} --out=${warp_ct}2
    # printf "!!\n" >> ${rlog}

    printf "invwarp --ref=${f_ct} --warp=${warp_ct_transf} --out=${inv_warp_ct_transf}\n" >> ${rlog}
    invwarp --ref=${f_ct} --warp=${warp_ct_transf} --out=${inv_warp_ct_transf}
    # printf "!!\n" >> ${rlog}

    # concatenate transformation matrix
    printf "# Concatenate transformation matrix ${mr2std_mat} & ${aff_mat}\n" >> ${rlog}
    printf "convert_xfm -omat ${ct2std_mat} -concat ${mr2std_mat} ${aff_mat}\n" >> ${rlog}
    convert_xfm -omat ${ct2std_mat} -concat ${mr2std_mat} ${aff_mat}
    # printf "!!\n" >> ${rlog}

    printf "# Inverse transformation matrix from standard space to CT space\n" >> ${rlog}
    printf "convert_xfm -omat ${inv_ct2std_mat} -inverse ${ct2std_mat}\n" >> ${rlog}
    convert_xfm -omat ${inv_ct2std_mat} -inverse ${ct2std_mat}
    # printf "!!\n" >> ${rlog}

    printf "cp ${ct2std_mat} ${aff_ct2std}\n" >> ${rlog}
    cp ${ct2std_mat} ${aff_ct2std}
    # printf "!!\n" >> ${rlog}
    printf "cp ${inv_ct2std_mat} ${inv_aff_ct2std}\n" >> ${rlog}
    cp ${inv_ct2std_mat} ${inv_aff_ct2std}
    # printf "!!\n" >> ${rlog}

    # brain mask in CT space
    mr_mask=${subjdir}/${mr}_brain_mask.nii.gz
    if [[ ! -f "${mr_mask}" ]]; then
        printf "fslmaths ${subjdir}/${mr}_brain -bin -fillh -bin ${mr_mask}\n" >> ${rlog}
        fslmaths ${subjdir}/${mr}_brain -bin -fillh -bin ${mr_mask}
    fi

    printf "flirt -in ${mr_mask} -ref ${f_ct} -applyxfm -init ${inv_aff_mat} -out ${ct_mask}\n" >> ${rlog}
    flirt -in ${mr_mask} -ref ${f_ct} -applyxfm -init ${inv_aff_mat} -out ${ct_mask}
    # printf "!!\n" >> ${rlog}

else # Only CT was available
    if [[ -f ${ct2std}  && ${re_run} -eq 1 ]]; then
        printf "# CT image has already been registered to the standard brain.\n" >> ${rlog}

    else
        printf "# Registering CT image to directly to the standard brain, this may not be accurate.\n" >> ${rlog}
        printf "flirt -in ${f_ct} -ref ${std} -dof 12 -cost mutualinfo -searchcost mutualinfo -omat ${aff_ct2std} -out ${ct2std}\n" >> ${rlog}
        flirt -in ${f_ct} -ref ${std} -dof 12 -cost mutualinfo -searchcost mutualinfo -omat ${aff_ct2std} -out ${ct2std}
        # printf "!!\n" >> ${rlog}

        printf "# Inverse transformation matrix from standard space to CT space\n" >> ${rlog}
        printf "convert_xfm -omat ${inv_aff_ct2std} -inverse ${aff_ct2std}\n" >> ${rlog}
        convert_xfm -omat ${inv_aff_ct2std} -inverse ${aff_ct2std}
        # printf "!!\n" >> ${rlog}

        printf "flirt -in ${std}_mask -ref ${f_ct} -applyxfm -init ${inv_aff_ct2std} -out ${ct_mask}\n" >> ${rlog}
        flirt -in ${std}_mask -ref ${f_ct} -applyxfm -init ${inv_aff_ct2std} -out ${ct_mask}
        # printf "!!\n" >> ${rlog}
    fi
fi

printf "# Binarizing CT mask.\n" >> ${rlog}
printf "fslmaths ${ct_mask} -bin ${ct_mask}\n" >> ${rlog}
fslmaths ${ct_mask} -bin ${ct_mask}
# printf "!!\n" >> ${rlog}
###### End of registration of CT images ######

printf "# *********Job finished at %s*********\n" $(date +%Y-%m-%d_%H:%M:%S) >> ${rlog}

## end of script
