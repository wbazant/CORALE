#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use File::Basename;


my ($dir, $pattern, $chosenColumn, $outputType) = @ARGV;
sub usage {
  die "Usage: $0 dir pattern <column|cpm> <matrix|triples>";
}
usage()  unless -d $dir && $pattern;

$chosenColumn //= 'cpm';
$outputType //= 'matrix';
usage() unless $outputType eq 'matrix' or $outputType eq 'triples';

opendir(my $dh, $dir) || die "Can't opendir $dir: $!";
my @files = grep {$_=~m{$pattern}} readdir($dh);
closedir $dh;

die "No files in input directory" unless @files;

my %sampleLabels;

sub firstIndex {
  my ($chosenColumn, $line) = @_;
  for my $ix (0..$#$line){
    if ($line->[$ix] eq $chosenColumn){
      return $ix;
    }
  }
  return -1;
}

my %result;
my @result;
for my $file (@files){
  open(my $fh, "<", "$dir/$file") or die "$!: $file";
  my $name = $file;
  if( -l "$dir/$file" ){
    my $f = readlink "$dir/$file";
    $name = basename $f;
  }
  my ($sample) = $name =~ m{(.*)$pattern};
  $sampleLabels{$sample}++;
  die $file unless $sample;
  my $chosenColumnIndex;
  while(<$fh>){
    chomp;
    my @line = split "\t";

    if ($. == 1){
      $chosenColumnIndex = firstIndex($chosenColumn, \@line);
      die "Could not find value column $chosenColumn in $file, header not recognised: $_" unless $chosenColumnIndex > -1;
    } else{
      my $taxon = $line[0];
      my $value = $line[$chosenColumnIndex];
      push @result, [$sample, $taxon, $value];
    }
  }
}

my @sampleLabels = sort keys %sampleLabels;
my $n1 = scalar @files;
my $n2 = scalar @sampleLabels;
die "Number of input files ($n1) and different value column labels ($n2) doesn't match"
  unless $n1 == $n2;

print_matrix(\@result, \@sampleLabels) if $outputType eq 'matrix';
print_triples(\@result) if $outputType eq 'triples';

sub print_matrix {
  my ($result, $sampleLabels) = @_;
  my %result;
  for my $t (@{$result}){
    my ($sample, $taxon, $value) = @$t;
    $result{$taxon}{$sample} = $value;
  }

  say join "\t", "", @{$sampleLabels};
  for my $key (sort keys %result){
    my %h = %{$result{$key}};
    say join "\t", $key, map {$_ // ""} @h{@sampleLabels};
  }
}

sub print_triples {
  my ($result) = @_;
  for my $t (@{$result}){
    say join "\t", @$t;
  }
}
