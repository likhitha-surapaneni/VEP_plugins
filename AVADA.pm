=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2023] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

 Ensembl <http://www.ensembl.org/info/about/contact/index.html>

=cut

=head1 NAME

 AVADA

=head1 SYNOPSIS
./vep -i variations.vcf --plugin AVADA,file=path/to/file
./vep -i variations.vcf --plugin AVADA,file=path/to/file,feature_match_by=<gene_symbol|ensembl_gene_id|refseq_transcript_id|refseq_protein_id>

=head1 DESCRIPTION

Automatic VAriant evidence DAtabase is a novel machine learning tool that uses natural language processing 
to automatically identify pathogenic genetic variant evidence in full-text primary literature about 
monogenic disease and convert it to genomic coordinates.

Please cite the AVADA publication alongside the VEP if you use this resource:
https://pubmed.ncbi.nlm.nih.gov/31467448/

NB: The plugin currently does not annotate for downstream_gene_variant and upstream_gene_variant 

Pre-requisites
1) AVADA data is available for GRCh37 and can be downloaded from: 
http://bejerano.stanford.edu/AVADA/avada_v1.00_2016.vcf.gz

wget http://bejerano.stanford.edu/AVADA/avada_v1.00_2016.vcf.gz

2) The file needs to be tabix indexed. You can do this by following commands:

gzip -d avada_v1.00_2016.vcf.gz
bgzip avada_v1.00_2016.vcf 
tabix avada_v1.00_2016.vcf.gz

3) As you have already noticed, tabix utility must be installed in your path to use this plugin. 

Options are passed to the plugin as key=value pairs:

The plugin can then be run to retrieve AVADA annotations. 
By default, the variants are matched with the HGNC gene symbol
./vep -i variations.vcf --plugin AVADA,file=path/to/file

The output always includes two columns:
AVADA_FEATURE_ID: Feature ID associated with variant as reported by AVADA
AVADA_PMID: PubMed ID evidence for the variant as reported by AVADA

The plugin can optionally be run by specifying the feature to match with

In order to match by HGNC gene symbol:
./vep -i variations.vcf --plugin AVADA,file=path/to/file,feature_match_by=gene_symbol 

In order to match by ENSEMBL gene identifier :
./vep -i variations.vcf --plugin AVADA,file=path/to/file,feature_match_by=ensembl_gene_id

In order to match by RefSeq transcript identifier :
./vep -i variations.vcf --plugin AVADA,file=path/to/file,feature_match_by=refseq_transcript_id

In order to match by RefSeq protein identifier :
./vep -i variations.vcf --plugin AVADA,file=path/to/file,feature_match_by=refseq_protein_id



=cut

package AVADA;

use strict;
use warnings;
use Data::Dumper;
use List::MoreUtils qw(uniq);
use Bio::EnsEMBL::Variation::Utils::BaseVepTabixPlugin;
use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepTabixPlugin);



my $feature_match_by;

sub get_header_info {
  my $self = shift;
  my %header;

  $header{"AVADA_FEATURE_ID"} = "Feature ID associated with variant as reported by AVADA" ; 
  $header{"AVADA_PMID"} = "PubMed ID evidence for the variant as reported by AVADA"; 
  return \%header
}

sub new {
  my $class = shift;
  
  my $self = $class->SUPER::new(@_);

  $self->expand_left(0);
  $self->expand_right(0);

  $self->get_user_params();
  my $param_hash = $self->params_to_hash();
  my $file = $param_hash->{file};
  die "\n  ERROR: No file specified\nTry using 'AVADA,file=path/to/file.tsv.gz'\n" unless defined($file);
  $self->add_file($file);
  $feature_match_by = $param_hash->{feature_match_by}; 
  if (defined($feature_match_by) && $feature_match_by  eq "refseq_transcript_id") {
    $self->{config}->{refseq} = 1 unless $self->{config}->{database} == 1 ; # when using db, refseq is not enabled in spite of forcing in code
    # Currently sets use_given_ref to 1 always
    $self->{config}->{use_given_ref} = 1;
    die "\n ERROR: Matching by Refseq ID requires the option --refseq when using the database  \n" if $self->{config}->{refseq} == 0 && $self->{config}->{database} == 1;
  }
  return $self;
}

sub run {
  my ($self, $tva) = @_;

  return {} if grep {$_->SO_term eq 'downstream_gene_variant' || $_->SO_term eq 'upstream_gene_variant'} @{$tva->get_all_OverlapConsequences};

  my $vf = $tva->variation_feature;
  my $tv = $tva->transcript_variation;
  my $end = $vf->{end};
  my $start = $vf->{start};
  my $transcript = $tva->transcript;
  my %output;
  my @data;

  if (!defined($feature_match_by)){
    @data = @{$self->get_data($vf->{chr}, $start, $end)};
    $output{"AVADA_FEATURE_ID"} = $data[0]->{AVADA_GENE_SYMBOL}  if scalar @data && defined $data[0]->{AVADA_GENE_SYMBOL} ; 
  }
  elsif ( $feature_match_by eq "gene_symbol"){
    @data = grep {
    $_->{AVADA_GENE_SYMBOL} eq $transcript->{_gene_symbol}
    }@{$self->get_data($vf->{chr}, $start, $end)};
    $output{"AVADA_FEATURE_ID"} = $data[0]->{AVADA_GENE_SYMBOL} if scalar @data && defined $data[0]->{AVADA_GENE_SYMBOL} ; ;
  }
  elsif ( $feature_match_by eq "refseq_transcript_id" ){
    my $refseq_transcript = $transcript->{stable_id};
    @data = grep {
      $_->{AVADA_REFSEQ_ID} eq $refseq_transcript 
      }@{$self->get_data($vf->{chr}, $start, $end)};
    $output{"AVADA_FEATURE_ID"} = $data[0]->{AVADA_REFSEQ_ID} if scalar @data && defined $data[0]->{AVADA_REFSEQ_ID} ;
  }
  elsif ( $feature_match_by eq "refseq_protein_id" ){
    my $refseq_protein = $transcript->translation->{stable_id};
    $refseq_protein =~ s/cds-// if $self->{config}->{database} == 1;
    @data = grep {
      $_->{AVADA_REFSEQ_ID} eq $refseq_protein
      }@{$self->get_data($vf->{chr}, $start, $end)};
    $output{"AVADA_FEATURE_ID"} = $data[0]->{AVADA_REFSEQ_ID} if scalar @data && defined $data[0]->{AVADA_REFSEQ_ID} ;
  }
  elsif ( $feature_match_by eq "ensembl_gene_id" ){
  @data = grep {
    $_->{AVADA_ENSEMBL_ID} eq $transcript->{_gene_stable_id}
    }@{$self->get_data($vf->{chr}, $start, $end)};
  $output{"AVADA_FEATURE_ID"} =  $data[0]->{AVADA_ENSEMBL_ID} if scalar @data && defined $data[0]->{AVADA_ENSEMBL_ID} ;
  }
  else{
    die("ERROR: feature_match_by can only take one of the options gene_symbol|ensembl_gene_id|refseq_transcript_id ");
  }
  return {} unless scalar @data;
  my $pmid_string ;
  my %seen;
  foreach my $data_value (uniq @data) {
    next unless ( ! exists $seen{$data_value->{AVADA_PMID}} );
    $pmid_string = $pmid_string ? $pmid_string.",".$data_value->{AVADA_PMID} : $data_value->{AVADA_PMID}; 
    $seen{$data_value->{AVADA_PMID}} = 1;   
  }
  
  $output{"AVADA_PMID"} = $pmid_string;
  return \%output;
}

sub parse_data {
  my ($self, $line) = @_;
  my ($chr, $start, $id, $ref, $alt, $x, $xx, $data) = split /\t/, $line;
  my ($pmid, $ensembl_gene_id, $gene_symbol, $refseq_transcript_id, $original_variant_string);
  my @data_split = split /;/, $data;
  foreach my $value (@data_split){
      $pmid = $value if $value =~ /PMID/;
      $ensembl_gene_id = $value if $value =~ /ENSEMBL_ID/; 
      $gene_symbol = $value if $value =~ /GENE_SYMBOL/; 
      $refseq_transcript_id = $value if $value =~ /REFSEQ_ID/; 
      $original_variant_string = $value if $value =~ /ORIGINAL_VARIANT_STRING/;

  }
  $pmid =~ s/PMID=//;
  $ensembl_gene_id =~ s/ENSEMBL_ID=//;
  $gene_symbol =~ s/GENE_SYMBOL=//;
  $refseq_transcript_id =~ s/REFSEQ_ID=//;
  $original_variant_string =~ s/ORIGINAL_VARIANT_STRING=//;
  return {
    AVADA_PMID => $pmid,
    AVADA_ENSEMBL_ID => $ensembl_gene_id,
    AVADA_GENE_SYMBOL => $gene_symbol,
    AVADA_REFSEQ_ID => $refseq_transcript_id,
    AVADA_VARIANT_STRING => $original_variant_string
  };
}

1;
