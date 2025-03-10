### Pipeline for analysing allele frequencies and variants detected by ANGSD in low coverage LHISI data
### This can only be run once SnakefileAlleleFrequencies has been run and the ngsParalog analysis has been run

### Also run the script `build_snpeff_database.sh`

HOME_DIR=/Volumes/Alter/Daus_WGS_Paper
REF_DIR=${HOME_DIR}/References
WORKING_DIR=${HOME_DIR}/Analysis/DeleteriousMutations
DATA_DIR=${HOME_DIR}/Analysis/AlleleFrequencies

cd ${WORKING_DIR}

### We start by looping over the sites used to estimate allele frequencies
### We estimated frequencies one scaffold at a time, so we need to concatenate the outputs
### We have also used the allele frequency outputs to estimate regions of problematic mapping
### We remove these sites from the list, first converting to a bed, then using bedtools, then converting the output to the usual "chr\tpos" format

conda activate fasta_manipulation_env

for scaf in $(cat ${REF_DIR}/autosome_names)

	do
	gzcat ${DATA_DIR}/${scaf}_all.mafs.gz | \
	awk 'NR > 1 {print $1"\t"$2-1"\t"$2"\t"$3"\t"$4}' >> tmp.bed

done

sort -k1,1 -k2,2n tmp.bed | uniq > tmp_uniq.bed

cat ../ngsParalogAnalysis/problematic_regions.bed ${REF_DIR}/Annotation/repeats_major.bed |
sort -k1,1 -k2,2n | \
bedtools merge -i stdin > tmp_2.bed

bedtools subtract -a tmp_uniq.bed -b tmp_2.bed | \
cut -f1,3,4,5 > vars.txt

rm tmp*

### This cuts out ~20% of sites

### Now we turn this into a dummy vcf file

echo -e "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO" > dummy.vcf
awk '{print $1"\t"$2"\t"$1"_"$2"\t"$3"\t"$4"\t100.00\tPASS\tNA"}' vars.txt >> dummy.vcf

### Now we use snpEff to estimate the effects of all these variants
### Most will be nothing, since they're not inside genes, and snpEff can only use gene annotations
### Also this relies on already having the snpEff database set up

java -jar ~/snpEff/snpEff.jar eff Daus2.0 dummy.vcf -o gatk > vars_classified.vcf

### Clean up the output to make it a nice table
### This code is so UGLY

awk 'NR > 5 {print $8}' vars_classified.vcf > tmp
cut -d "=" -f2 tmp | cut -d "(" -f1 > tmp1
cut -d "(" -f2 tmp | cut -d "|" -f1 > tmp2
cut -d "(" -f2 tmp | cut -d "|" -f2 > tmp3
cut -d "(" -f2 tmp | cut -d "|" -f3 > tmp4
cut -d "(" -f2 tmp | cut -d "|" -f4 > tmp5
cut -d "(" -f2 tmp | cut -d "|" -f5 > tmp6
cut -d "(" -f2 tmp | cut -d "|" -f6 > tmp7
cut -d "(" -f2 tmp | cut -d "|" -f7 > tmp8
cut -d "(" -f2 tmp | cut -d "|" -f8 > tmp9
cut -d "(" -f2 tmp | cut -d "|" -f9 > tmp10

awk 'NR > 5 {print $1"\t"$2}' vars_classified.vcf > left

echo -e "Scaffold\tPosition\tVariant_Type\tVariant_Effect\tEffect_Impact\tCodon_Change\tAA_Change\tGene\tGene_Type\tGene_Region\tGene_Transcript\tGene_Exon" > vars_classified.txt

paste left tmp1 tmp2 tmp3 tmp4 tmp5 tmp6 tmp7 tmp8 tmp9 tmp10 | \
sed 's/\t\t/\tNA\t/g' | \
sed 's/\t\t/\tNA\t/g' | \
sed 's/)//g' | \
sed 's/\t$/\tNA/g' >> vars_classified.txt

rm left tmp* dummy*

### We're also going to get a list of gene annotation scores (annotation edit distances)
### We'll use these to stratify the analyses and be more rigourous

echo -e "Gene\tAED\teAED" > gene_scores.txt

gzcat ${REF_DIR}/Annotation/LHISI_Scaffold_Assembly.original_annotation.gff.gz | \
awk '$3 == "mRNA"' | \
cut -f9 | \
cut -d ";" -f2,4,5 | \
sed 's/Parent=//g' | \
sed -E 's/_e?AED=//g' | \
tr ";" "\t" >> gene_scores.txt

# We're also going to use the ROH bed files generated in ../GenotypeLikelihoodROH
# For each population we'll get per-site % coverage by ROH

ROH_DIR=../GenotypeLikelihoodROH
awk 'NR > 1 {print $1"\t"$2-1"\t"$2}' vars_classified.txt > vars.tmp

# LHIP

cat ${REF_DIR}/wgs_sample_details.txt | \
grep "C01230\|C01225\|C10223\|C01211\|C01217\|C01220\|C01234\|C01224" | \
cut -f1 > tmp

for f in $(cat tmp)
	do

	cat ${ROH_DIR}/${f}_rohs.bed >> tmp.bed

	done

sort -k1,1 -k2,2n tmp.bed | \
bedtools coverage -a vars.tmp -b stdin -d | \
awk '{print $1"\t"$3"\t"$5/8}' > LHIP.cov

rm tmp*


# LHISI

cat ${REF_DIR}/wgs_sample_details.txt | \
grep "C01210\|C01215\|C01223\|C01222\|C01232\|C01231\|C01219\|C01227\|C01213" | \
cut -f1 > tmp

for f in $(cat tmp)
	do

	cat ${ROH_DIR}/${f}_rohs.bed >> tmp.bed

	done

sort -k1,1 -k2,2n tmp.bed | \
bedtools coverage -a vars.tmp -b stdin -d | \
awk '{print $1"\t"$3"\t"$5/9}' > LHISI.cov

rm tmp*

# WILD

cat ${REF_DIR}/wgs_sample_details.txt | \
grep "PAUL\|VAN" | \
cut -f1 > tmp

for f in $(cat tmp)
	do

	cat ${ROH_DIR}/${f}_rohs.bed >> tmp.bed

	done

sort -k1,1 -k2,2n tmp.bed | \
bedtools coverage -a vars.tmp -b stdin -d | \
awk '{print $1"\t"$3"\t"$5/2}' > WILD.cov

rm tmp*

# Finally, we're going to score genes by whether they are masked by repeatmasker
# If a gene has any overlap with a repeat it is removed

gzcat ${REF_DIR}/Annotation/LHISI_Scaffold_Assembly.original_annotation.gff.gz | \
awk '$3 == "gene" {print $1"\t"$4"\t"$5"\t"$9}' > gene_coords.bed
bedtools subtract -a gene_coords.bed -b ${REF_DIR}/Annotation/repeats.bed -A > gene_coords_masked.bed
cut -d ";" -f1 gene_coords_masked.bed | cut -d "=" -f2 > unmasked_genes
