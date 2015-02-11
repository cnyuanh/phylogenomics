#!/usr/bin/perl

# WARNING: this only handles a single genbank file per program.
# TODO: object-orient this.

package Genbank;
use strict;
use FindBin;
use lib "$FindBin::Bin/..";
use Subfunctions qw(split_seq reverse_complement);
use Data::Dumper;


BEGIN {
	require Exporter;
	# set the version for version checking
	our $VERSION     = 1.00;
	# Inherit from Exporter to export functions and variables
	our @ISA         = qw(Exporter);
	# Functions and variables which are exported by default
	our @EXPORT      = qw(parse_genbank sequence_for_interval sequin_feature stringify_feature flatten_interval parse_feature_desc parse_interval parse_qualifiers within_interval write_sequin_tbl write_region_array parse_region_array parse_featurefile parse_feature_table parse_gene_array_to_features set_sequence get_sequence get_name write_features_as_fasta write_features_as_table clone_features);
	# Functions and variables which can be optionally exported
	our @EXPORT_OK   = qw();
}

# my @gene_array = ();
my $line = "";
my $in_features = 0;
my $in_sequence = 0;
my $feat_desc_string = "";
my $sequence = "";
my $curr_gene = {};
my $gb_name = "";

sub set_sequence {
	$sequence = shift;
}

sub get_sequence {
	return $sequence;
}

sub get_name {
	return $gb_name;
}


sub parse_genbank {
	my $gbfile = shift;

	open FH, "<", $gbfile;

	my @gene_array = ();
	$line = "";
	$in_features = 0;
	$in_sequence = 0;
	$feat_desc_string = "";
	$sequence = "";
	$curr_gene = {};
	$gb_name = "";

	$line = readline FH;
	while (defined $line) {
		if ($line =~ /^\s+$/) {
			# if the line is blank, skip to end
		} elsif ($line =~ /^\/\//) { # we've finished the file
			last;
		} elsif ($line =~ /^\S/) { # we're looking at a new section
			if ($line =~ /DEFINITION\s+(.*)$/) { # if line has the definition, keep this.
				$gb_name = $1;
			} elsif ($line =~ /FEATURES/) { # if we hit a line that says FEATURES, we're starting the features.
				$in_features = 1;
			} elsif ($line =~ /ORIGIN/) { # if we hit a line that says ORIGIN, we have sequence
				# this is the end of the features: process the last feature and finish.
				parse_feature_desc ($feat_desc_string, \@gene_array);
				$in_features = 0;
				$in_sequence = 1;
			}
		} elsif ($in_sequence == 1) {
			$line =~ s/\d//g;
			$line =~ s/\s//g;
			$sequence .= $line;
			# process lines in the sequence.
		} elsif ($in_features == 1) {
			# three types of lines in features:
			if ($line =~ /^\s{5}(\S.+)$/) {
				# start of a feature descriptor. Parse whatever feature and qualifiers we might've been working on and move on.
				if ($feat_desc_string ne "") {
					my $feat_desc_hash = parse_feature_desc ($feat_desc_string, \@gene_array);
				}
				$feat_desc_string = $1;
			} elsif ($line =~ /^\s{21}(\S.+)$/) {
				$feat_desc_string .= "+$1";
			}
		}

		$line = readline FH;
	}
	close FH;
	return \@gene_array;
}

sub parse_feature_sequences {
	my $gene_array = shift;

	my $gene_id = 0;
	foreach my $gene (@$gene_array) {
		if ($gene->{"type"} eq "gene") {
			my $interval_str = flatten_interval ($gene->{"region"});
			my $geneseq = sequence_for_interval ($interval_str);
			my $genename = $gene->{"qualifiers"}->{"gene"};
			foreach my $feat (@{$gene->{"contains"}}) {
				my $feat_id = 0;
				foreach my $reg (@{$feat->{"region"}}) {
					my $strand = "+";
					my ($start, $end) = split (/\.\./, $reg);
					if ($end < $start) {
						$strand = "-";
						my $oldend = $start;
						$start = $end;
						$end = $oldend;
					}
					my $regseq = sequence_for_interval ($reg);
					my $featname = $feat->{"type"};
# 					$gene_array[$gene_id]"."_$feat_id"."_$genename"."_$featname($strand)\t$start\t$end\n$regseq\n";
					$feat_id++;
				}
			}
			my $interval_str = flatten_interval ($gene->{"region"});
			my @gene_interval = ($interval_str);
			$gene_id++;
		}
	}
}

sub clone_features {
	my $gene_array = shift;
# print Dumper ($gene_array);
	my $flattened_hash = {};
	my @flattened_names = ();
	my $gene_id = 0;

	foreach my $gene (@$gene_array) {
		if ($gene->{"type"} eq "gene") {
			my $interval_str = flatten_interval ($gene->{"region"});
			my @gene_interval = ($interval_str);
			my $genename = $gene->{"qualifiers"}->{"gene"};
			$flattened_hash->{$genename}->{"gene"} = stringify_feature(\@gene_interval, $gene);
# 			$result .= "$gene_id\t" . stringify_feature(\@gene_interval, $gene);
			$flattened_hash->{$genename}->{"contains"} = ();
			foreach my $feat (@{$gene->{"contains"}}) {
				push @{$flattened_hash->{$genename}->{"contains"}}, stringify_feature($feat->{"region"}, $feat);
# 				$result .= "$gene_id\t" . stringify_feature ($feat->{"region"}, $feat);
				my $feat_id = 0;
				foreach my $reg (@{$feat->{"region"}}) {
					my $strand = "+";
					my ($start, $end) = split (/\.\./, $reg);
					if ($end < $start) {
						$strand = "-";
						my $oldend = $start;
						$start = $end;
						$end = $oldend;
					}
					my $regseq = sequence_for_interval ($reg);
					my $featname = $feat->{"type"};
					my $fullname = "$gene_id"."_$feat_id"."_$genename"."_$featname";
					push @flattened_names, $fullname;
					$flattened_hash->{$fullname}->{"strand"} = $strand;
					$flattened_hash->{$fullname}->{"start"} = $start;
					$flattened_hash->{$fullname}->{"end"} = $end;
					$flattened_hash->{$fullname}->{"characters"} = $regseq;
					$feat_id++;
				}
			}
			$gene_id++;
		}
	}
# 	print Dumper ($flattened_hash);
	return ($flattened_hash, \@flattened_names);
}

sub write_features_as_fasta {
	my $gene_array = shift;

	my ($flattened_hash, $flattened_names) = clone_features ($gene_array);
	my $result = "";
	foreach my $fullname (@$flattened_names) {
		my $strand = $flattened_hash->{$fullname}->{"strand"};
		my $start = $flattened_hash->{$fullname}->{"start"};
		my $end = $flattened_hash->{$fullname}->{"end"};
		my $regseq = $flattened_hash->{$fullname}->{"characters"};
		$result .= ">$fullname($strand)\t$start\t$end\n$regseq\n";
	}

	return $result;
}

sub write_features_as_table {
	my $gene_array = shift;
	my $result = "";
	my $gene_id = 0;
	foreach my $gene (@$gene_array) {
		if ($gene->{"type"} eq "gene") {
			my $interval_str = flatten_interval ($gene->{"region"});
			my @gene_interval = ($interval_str);
			$result .= "$gene_id\t" . stringify_feature(\@gene_interval, $gene);
			foreach my $feat (@{$gene->{"contains"}}) {
				$result .= "$gene_id\t" . stringify_feature ($feat->{"region"}, $feat);
			}
			$gene_id++;
		}
	}

	return $result;
}

sub write_sequin_tbl {
	my $gene_array = shift;
	my $name = shift;

	# print header
	my $result = ">Features\t$name\n";

	# start printing genes
	foreach my $gene (@$gene_array) {
		# first, print overall gene information
		my $genename = $gene->{"qualifiers"}->{"gene"};
		foreach my $r (@{$gene->{'region'}}) {
			$r =~ /(\d+)\.\.(\d+)/;
			$result .= "$1\t$2\tgene\n";
		}
		foreach my $q (keys %{$gene->{'qualifiers'}}) {
			$result .= "\t\t\t$q\t$gene->{qualifiers}->{$q}\n";
		}

		# then, print each feature contained.
		foreach my $feat (@{$gene->{'contains'}}) {
			foreach my $reg (@{$feat->{"region"}}) {
				my $strand = "+";
				my ($start, $end) = split (/\.\./, $reg);
				if ($end < $start) {
					$strand = "-";
					my $oldend = $start;
					$start = $end;
					$end = $oldend;
				}
			}
			$result .= Genbank::sequin_feature ($feat->{'region'}, $feat);
		}
	}

	return $result;

}

sub parse_feature_table {
	my $featuretablestring = shift;

	my @featuretable = split (/\n|\r/,$featuretablestring);
	my @gene_hasharray = ();
	my @gene_index_array = ();
	my $gene_id = -1;
	my $curr_gene = {};
	foreach my $line (@featuretable) {
		my ($id, $type, $regionstr, $qualstr, undef) = split ("\t", $line);
		# first, assemble the feature into a hash.
		my $this_feat = {};
		$this_feat->{"qualifiers"} = {};
		my @quals = split("#", $qualstr);
		foreach my $q (@quals) {
			if ($q =~ /^(.*?)=(.*)$/) {
				$this_feat->{"qualifiers"}->{$1} = $2;
			}
		}
		$this_feat->{"region"} = ();
		my @regions = split(",", $regionstr);
		foreach my $r (@regions) {
			push @{$this_feat->{"region"}}, $r;
		}

		$this_feat->{"type"} = $type;
		# then, check to see if this is a subfeature of the current gene (if its id # is the same as the current gene_id)
		if ($id == $gene_id) {
			# if it is, push it into the "contains" array.
			push @{$curr_gene->{"contains"}}, $this_feat;
		} else {
			$gene_id = $id;
			$curr_gene = $this_feat;
			push @gene_index_array, $id;
			push @gene_hasharray, $curr_gene;
		}
	}
	return (\@gene_hasharray, \@gene_index_array);
}

sub parse_gene_array_to_features {
	my $gene_array = shift;

	my @gene_hasharray = ();
	my @gene_index_array = ();
	my @featuretable = ();
	my $gene_id = 0;
	foreach my $gene (@$gene_array) {
		if ($gene->{"type"} eq "gene") {
			my $interval_str = flatten_interval ($gene->{"region"});
			my $geneseq = sequence_for_interval ($interval_str);
			my $genename = $gene->{"qualifiers"}->{"gene"};
			foreach my $feat (@{$gene->{"contains"}}) {}
			my $interval_str = flatten_interval ($gene->{"region"});
			my @gene_interval = ($interval_str);
			push @featuretable, "$gene_id\t" . stringify_feature(\@gene_interval, $gene);
			foreach my $feat (@{$gene->{"contains"}}) {
				push @featuretable, "$gene_id\t" . stringify_feature ($feat->{"region"}, $feat);
			}
			$gene_id++;
		}
	}

	$gene_id = -1;
	my $curr_gene = {};
	foreach my $line (@featuretable) {
		my ($id, $type, $regionstr, $qualstr, undef) = split ("\t", $line);
		# first, assemble the feature into a hash.
		my $this_feat = {};
		$this_feat->{"qualifiers"} = {};
		my @quals = split("#", $qualstr);
		foreach my $q (@quals) {
			if ($q =~ /^(.*?)=(.*)$/) {
				$this_feat->{"qualifiers"}->{$1} = $2;
			}
		}
		$this_feat->{"region"} = ();
		my @regions = split(",", $regionstr);
		foreach my $r (@regions) {
			push @{$this_feat->{"region"}}, $r;
		}

		$this_feat->{"type"} = $type;
		# then, check to see if this is a subfeature of the current gene (if its id # is the same as the current gene_id)
		if ($id == $gene_id) {
			# if it is, push it into the "contains" array.
			push @{$curr_gene->{"contains"}}, $this_feat;
		} else {
			$gene_id = $id;
			$curr_gene = $this_feat;
			push @gene_index_array, $id;
			push @gene_hasharray, $curr_gene;
		}
	}
	return (\@gene_hasharray, \@gene_index_array);
}

sub parse_featurefile {
	my $featurefile = shift;

	open FH, "<:crlf", $featurefile or die "couldn't open file $featurefile";

	my $featuretable = "";
	foreach my $line (<FH>) {
		$featuretable .= $line;
	}

	close FH;
	return parse_feature_table ($featuretable);
}

sub write_region_array {
	my $ref_hash = shift;
	my $ref_array = shift;

	my @region_array = ();
	foreach my $subj (@$ref_array) {
		push @region_array, "$subj($ref_hash->{$subj}->{'strand'})\t$ref_hash->{$subj}->{'start'}\t$ref_hash->{$subj}->{'end'}\n";
	}
	return \@region_array;
}

sub parse_region_array {
	my $region_array = shift;

	my @gene_array = ();
	my $curr_gene_count = 0;
	my $curr_gene_exons;
	my $curr_gene = "";
	my $curr_gene_hash= {};
	foreach my $line (@$region_array) {
		if ($line =~ /^(.*?)_(\d+)_(.+?)_(.+?)\((.)\)\t(\d+)\t(\d+)$/) {
			# 	0_0_trnH_tRNA(-)	4	77
			my ($id, $sub, $name, $type, $strand, $start, $end) = ($1, $2, $3, $4, $5, $6, $7);
			if ($id == 0) { # first gene
				$curr_gene_hash = {};
				$curr_gene_hash->{'id'} = $id;
				push @gene_array, $curr_gene_hash;
				# process new gene's first exon:
				$curr_gene_exons = ();
				my $region = "";
				if ($strand eq "-") {
					$region = "$end..$start";
				} else {
					$region = "$start..$end";
				}
				push @$curr_gene_exons, $region;
				my @feat_array = ();
				push @feat_array, {"region"=>$curr_gene_exons, "type"=>$type};
				$curr_gene_hash->{"contains"} = \@feat_array;
				$curr_gene_hash->{"qualifiers"} = {"gene"=>$name};
				$curr_gene = $name;
				next;
			}

			if ($id == $curr_gene_count) {
				# this is another exon in the same gene
				my $region = "";
				if ($strand eq "-") {
					$region = "$end..$start";
				} else {
					$region = "$start..$end";
				}
					push @$curr_gene_exons, $region;
			} else {
				# this is a new gene

				# finish processing the gene we were working on:
				$curr_gene_hash->{"type"} = "gene";
				$curr_gene_hash->{"region"} = max_interval ($curr_gene_exons); # largest gene region

				# start processing the new gene:
				$curr_gene_count = $id;
				$curr_gene_hash = {};
				$curr_gene_hash->{'id'} = $id;
				push @gene_array, $curr_gene_hash;

				# process new gene's first exon:
				$curr_gene_exons = ();
				my $region = "";
				if ($strand eq "-") {
					$region = "$end..$start";
				} else {
					$region = "$start..$end";
				}
				push @$curr_gene_exons, $region;
				my @feat_array = ();
				push @feat_array, {"region"=>$curr_gene_exons, "type"=>$type};
				$curr_gene_hash->{"contains"} = \@feat_array;
				$curr_gene_hash->{"qualifiers"} = {"gene"=>$name};
				$curr_gene = $name;
			}
		}
	}
	# finish processing the gene we were working on:
	$curr_gene_hash->{"type"} = "gene";
	$curr_gene_hash->{"region"} = max_interval ($curr_gene_exons); # largest gene region

	return \@gene_array;
}

sub sequence_for_interval {
	my $interval_str = shift;
	my $revcomp = shift;

	$interval_str =~ /(\d+)\.\.(\d+)/;
	my $start = $1;
	my $end = $2;
	my $geneseq = "";
	if ($start < $end) {
		(undef, $geneseq, undef) = Subfunctions::split_seq ($sequence, $start, $end);
	} else {
		(undef, $geneseq, undef) = Subfunctions::split_seq ($sequence, $end, $start);
		if ($revcomp == 1) {
			$geneseq = reverse_complement ($geneseq);
		}
	}
	return $geneseq;
}

sub sequin_feature {
	my $regions = shift;
	my $feature = shift;
	my $result = "";
# print Dumper($feature) . join (",", @$regions) . "\n";
	my $first_int = shift @$regions;
	$first_int =~ /(\d+)\.\.(\d+)/;
	$result = "$1\t$2\t$feature->{type}\n";
	foreach my $int (@$regions) {
		$int =~ /(\d+)\.\.(\d+)/;
		$result .= "$1\t$2\n";
	}
	foreach my $key (keys %{$feature->{"qualifiers"}}) {
		$result .= "\t\t\t$key\t$feature->{qualifiers}->{$key}\n";
	}
	return $result;
}

sub stringify_feature {
	my $regions = shift;
	my $feature = shift;
	my $result = "";

	my @features = ();
	foreach my $key (keys %{$feature->{"qualifiers"}}) {
		my $feat = "$key=$feature->{qualifiers}->{$key}";
		push @features, $feat;
	}
	$result = "$feature->{type}\t".join(",",@$regions)."\t".join("#",@features)."\n";
	return $result;
}


sub flatten_interval {
	my $int_array = shift;

	# calculate the largest extent of the main interval.
	my @locs = ();
	foreach my $r (@$int_array) {
		if ($r =~ /(\d+)\.\.(\d+)/) {
			push @locs, $1;
			push @locs, $2;
		}
	}
	# sort all the listed locations, make the start be the smallest possible val and the end be the largest possible val.
	@locs = sort {$a <=> $b} @locs;
	my $main_start = shift @locs;
	my $main_end = pop @locs;

	# was the original interval complemented?
	my $r = @$int_array[0];#join (",", @$int_array);
	my ($loc1, $loc2) = split (/\.\./, $r);
	if ($loc1 < $loc2) {
		return "$main_start..$main_end";
	} else {
		return "$main_end..$main_start";
	}

}

sub parse_feature_desc {
	my $feat_desc_string = shift;
	my $gene_array_ptr = shift;

	my $feat_desc_hash = {};

	my ($feature_desc, @feature_quals) = split (/\+\//, $feat_desc_string);
	#parse feature_desc into name and interval.
	$feature_desc =~ s/\+//g;
	$feature_desc =~ /^(.{16})(.+)$/;
	my $type = $1;
	my $region = $2;
	$type =~ s/ *$//; # remove trailing blanks.

	$feat_desc_hash->{"type"} = $type;
	$feat_desc_hash->{"region"} = parse_interval($region);
	$feat_desc_hash->{"qualifiers"} = parse_qualifiers(\@feature_quals);
	if ($feat_desc_hash->{"type"} eq "gene") {
		$curr_gene = {};
		push @$gene_array_ptr, $curr_gene;
		$curr_gene->{"contains"} = ();
		$curr_gene->{"region"} = $feat_desc_hash->{"region"};
		$curr_gene->{"qualifiers"} = $feat_desc_hash->{"qualifiers"};
		$curr_gene->{"type"} = "gene";
	} else {
		if (within_interval($curr_gene->{"region"}, $feat_desc_hash->{"region"})) {
			# this feat_desc_hash belongs to the current gene.
			push @{$curr_gene->{"contains"}}, $feat_desc_hash;
		} else {
			$curr_gene = $feat_desc_hash;
			push @$gene_array_ptr, $feat_desc_hash;
		}
	}
	return $feat_desc_hash;
}

sub parse_interval {
	my $intervalstr = shift;
	my @regions = ();
	if ($intervalstr =~ /^complement\s*\((.+)\)/) {
		# this is a complementary strand feature.
		my $subregions = parse_interval($1);
		foreach my $subreg (@$subregions) {
			if ($subreg =~ /(\d+)\.\.(\d+)/) {
				unshift @regions, "$2..$1";
			}
		}
	} elsif ($intervalstr =~ /^join\s*\((.+)\)$/) {
		# this is a series of intervals
		my @subintervals = split(/,/, $1);
		foreach my $subint (@subintervals) {
			my $subregions = parse_interval($subint);
			push @regions, @$subregions;
		}
	} elsif ($intervalstr =~ /^order\s*\((.+)\)$/) {
		# this is a series of intervals, but there is no implication about joining them.
		my @subintervals = split(/,/, $1);
		my $max_interval = max_interval (\@subintervals);
		push @regions, @$max_interval;
	} elsif ($intervalstr =~ /(\d+)\.\.(\d+)/) {
		push @regions, "$intervalstr";
	}
	return \@regions;
}

sub parse_qualifiers {
	my $qualifiers_ref = shift;

	my @qualifiers = @$qualifiers_ref;
	my $feature_hash = {};
	while (@qualifiers > 0) {
		my $f = shift @qualifiers;
		$f =~ s/\+/ /g;
		if ($f =~ /(.+)=(.+)/) {
			my $key = $1;
			my $val = $2;
			if ($val =~ /"(.*)"/) {
				$val = $1;
			}
			if ($key eq "translation") {
				next;
				$val =~ s/ //g;
			}
			$feature_hash->{$key} = $val;
		} elsif ($f =~ /(.+)/) {
			my $key = $1;
			$feature_hash->{$key} = "";
		} else {
			print "haven't dealt with this: $f\n";
		}
	}
	return $feature_hash;
}

sub max_interval {
	my $regions = shift;
	# calculate the largest extent of the main interval.
	my @locs = ();
	my $strand = "+";
	foreach my $r (@$regions) {
		if ($r =~ /(\d+)\.\.(\d+)/) {
			push @locs, $1;
			push @locs, $2;
			if ($2 < $1) {
				$strand = "-";
			}
		}
	}
	# sort all the listed locations, make the start be the smallest possible val and the end be the largest possible val.
	@locs = sort {$a <=> $b} @locs;
	my $main_start = shift @locs;
	my $main_end = pop @locs;
	my @max_region = ();
	if ($strand eq "+") {
		push @max_region, "$main_start..$main_end";
	} else {
		push @max_region, "$main_end..$main_start";
	}
	return \@max_region;
}

sub within_interval {
	my $main_interval = shift;
	my $test_interval = shift;

	if (($main_interval eq "") || ($test_interval eq "")) {
		# if the interval we're testing for is blank, return 0.
		return 0;
	}

	if ((ref $test_interval) !~ /ARRAY/) {
		$test_interval = parse_interval($test_interval);
	}

	if ((ref $main_interval) !~ /ARRAY/) {
		$main_interval = parse_interval($main_interval);
	}

	# calculate the largest extent of the main interval.
	my @locs = ();
	foreach my $r (@$main_interval) {
		if ($r =~ /(\d+)\.\.(\d+)/) {
			push @locs, $1;
			push @locs, $2;
		}
	}
	# sort all the listed locations, make the start be the smallest possible val and the end be the largest possible val.
	@locs = sort {$a <=> $b} @locs;
	my $main_start = shift @locs;
	my $main_end = pop @locs;

	# do the same for the tested intervals.
	@locs = ();
	foreach my $r (@$test_interval) {
		if ($r =~ /(\d+)\.\.(\d+)/) {
			push @locs, $1;
			push @locs, $2;
		}
	}
	# sort all the listed locations, make the start be the smallest possible val and the end be the largest possible val.
	@locs = sort {$a <=> $b} @locs;
	my $test_start = shift @locs;
	my $test_end = pop @locs;
	if (($test_start >= $main_start) && ($test_end <= $main_end)) {
		return 1;
	}
	return 0;
}


return 1;

