### Pipeline for analysing depth and heterozygosity with ngsParalog
### Requires bedtools, samtools, Rscript in path
### Relies on ngsparalog being made

# Local config
#HOME_DIR=/Volumes/Alter/Daus_WGS_Paper
#REF_DIR=${HOME_DIR}/References
#ALN_DIR=${HOME_DIR}/Alignments/WGS
#WORKING_DIR=${HOME_DIR}/Analysis/ngsParalogAnalysis

# Dayhoff config
SCRATCH=/mnt/data/dayhoff/home/scratch/groups/mikheyev/LHISI
HOME_DIR=/mnt/data/dayhoff/home/u6905905
REF_DIR=${SCRATCH}/References
ALN_DIR=${SCRATCH}/Alignments/WGS
WORKING_DIR=${SCRATCH}/Analysis/ngsParalogAnalysis
NGSPARALOG=${HOME_DIR}/ngsParalog
SCRIPT_DIR=${HOME_DIR}/Scripts

cd ${WORKING_DIR}

# If we're on Dayhoff, we need to finagle the conda settings
#source ${HOME_DIR}/.bashrc
eval "$(conda shell.bash hook)"
conda activate paul4_env

# We start by looping over the sites used to estimate allele
# frequencies. We estimated frequencies one scaffold at a time
# so we need to concatenate the outputs.

for scaf in $(cat ${REF_DIR}/autosome_names)

do

	zcat ../AlleleFrequencies/${scaf}_all.mafs.gz | \
	awk 'NR > 1' | \
	cut -f1,2 >> vars.txt

done

# Now we run the ngsParalog analysis with all unfiltered bam
# files. This might take a while.

find $ALN_DIR | \
grep bam$ | \
grep -v "C01216\|C01233\|C01218\|C01226\|C10133\|_WGS" > bam_list.txt

samtools mpileup \
-b bam_list.txt \
-l vars.txt  \
-q 0 -Q 0--ff UNMAP,DUP | \
${NGSPARALOG}/ngsParalog calcLR \
-infile - -outfile lhisi_wgs \
-minQ 30 -minind 6 -mincov 2

# Now we use bedtools to get average coverage at all of these sites
awk '{print $1"\t"$2-1"\t"$2}' lhisi_wgs > vars_filtered.bed
awk '{print $1"\t"$3}' lhisi_wgs > vars_filtered.txt

for file in $(cat bam_list.txt)
do
PREFIX=$(echo ${file} | rev | cut -d "/"  -f1 | rev | cut -d "." -f1)
echo $PREFIX
mosdepth -t 24 --by vars_filtered.bed -n ${PREFIX} ${file}
rm *mosdepth* *csi
zcat ${PREFIX}.regions.bed.gz | cut -f4 > ${PREFIX}.tmp
rm ${PREFIX}.regions.bed.gz
done

# Paste the tmp files together, get row means with Rscript
paste *tmp > tmp
Rscript ${SCRIPT_DIR}/RScripts/row_sums.R
rm *tmp*

# Now paste to vars
paste vars_filtered.txt means > depths
rm means

# Now we run the dupHMM.R script

conda deactivate

conda activate duphmm_env

# Estimate HMM parameters
Rscript ${NGSPARALOG}/dupHMM.R  \
--lrfile lhisi_wgs \
--outfile params \
--covfile depths \
--n 19 \
--paramOnly 1 \
--lrquantile 0.98

# Run it properly
# Have to loop over chromosomes

for scaf in $(cat ${REF_DIR}/autosome_names)
do

awk -v scaffold=${scaf} '$1 == scaffold' lhisi_wgs > in1
awk -v scaffold=${scaf} '$1 == scaffold' depths > in2

Rscript ${NGSPARALOG}/dupHMM.R  \
--lrfile in1 \
--outfile problematic_regions_${scaf} \
--covfile in2 \
--n 19 \
--paramfile params.par \
--lrquantile 0.98

rm in1 in2

done

conda deactivate

cat problematic_regions* > problematic_regions.bed
rm *regions_*

# Now we have a list of regions which are difficult to map
# We can use these as an input to further analyses
# Copy this into the references directory

cp problematic_regions.bed ${REF_DIR}

# Now we do some quick analysis to see how much of our analysable regions have been removed

conda activate paul4_env

# How much is covered by this
bedtools merge -i problematic_regions.bed | \
awk '{print $3-$2}' | \
awk '{sum += $1} END {print sum}'

# How much is covered by the repeats
sort -k1,1 -k2,2n ${REF_DIR}/Annotation/repeats_major.bed | \
bedtools merge -i stdin | \
awk '{print $3-$2}' | \
awk '{sum += $1} END {print sum}'

# Now merge the two, how much is covered
cat problematic_regions.bed ${REF_DIR}/Annotation/repeats_major.bed |
sort -k1,1 -k2,2n | \
bedtools merge -i stdin > tmp

awk '{print $3-$2}' tmp | \
awk '{sum += $1} END {print sum}'

# Now how much of the variants are removed after considering the
wc -l vars_filtered.bed
bedtools subtract -a vars_filtered.bed -b tmp | wc -l

# Of the autosomal regions not in the repeat mask, how much is covered by these problematic regions
bedtools subtract \
-a $REF_DIR/autosome_regions.bed \
-b $REF_DIR/Annotation/repeats_major.bed > non_rep_autosomes.bed

bedtools subtract -a non_rep_autosomes.bed -b problematic_regions.bed | \
awk '{print $3-$2}' | \
awk '{sum += $1} END {print sum}'

awk '{print $3-$2}' non_rep_autosomes.bed | \
awk '{sum += $1} END {print sum}'
