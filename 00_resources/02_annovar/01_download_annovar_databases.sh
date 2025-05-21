#!/bin/bash

# Script to download the ANNOVAR databases for hg38
# Note: the databases should be updated regularly, so check the ANNOVAR website for the latest versions.
# https://annovar.openbioinformatics.org/en/latest/user-guide/download/ 

# Download ANNOVAR
wget http://www.openbioinformatics.org/annovar/download/0wgxR2rIVP/annovar.latest.tar.gz
tar xvfz annovar.latest.tar.gz
mv annovar 02_annovar
rm annovar.latest.tar.gz 

# Download cytoband database 
wget -c -P humandb https://hgdownload.soe.ucsc.edu/goldenPath/hg38/database/cytoBand.txt.gz && \
gunzip -f humandb/cytoBand.txt.gz && mv humandb/cytoBand.txt humandb/hg38_cytoBand.txt

# Download RefGene annotation 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar refGene humandb

# Download EnsGene annotation 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar ensGene humandb

# Download dbSNP 151 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar avsnp151 humandb

# Download ClinVar database (June 2024 version) 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar clinvar_20240611 humandb

# Download dbNSFP 47a 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar dbnsfp47a humandb

# Download dbscSNV 11 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar dbscsnv11 humandb

# Download ExAC 03 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar exac03 humandb

# Download gene4denovo201907 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar gene4denovo201907 humandb

# Download gnomAD 41 Exomes 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar gnomad41_exome humandb

# Download InterVar 20180118 
perl annotate_variation.pl -buildver hg38 -downdb -webfrom annovar intervar_20180118 humandb

