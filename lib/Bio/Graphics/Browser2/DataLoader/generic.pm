package Bio::Graphics::Browser2::DataLoader::generic;

# $Id$
use strict;
use Bio::DB::SeqFeature::Store;
use Carp 'croak';
use File::Basename 'basename';
use base 'Bio::Graphics::Browser2::DataLoader';

my @COLORS = qw(blue red orange brown mauve peach green cyan black ivory beige);

sub start_load {
    my $self = shift;
    my $track_name = $self->track_name;
    my $data_path  = $self->data_path;

    my $db     = $self->create_database($data_path);
    my $loader_class = $self->Loader;
    my $fast         = $self->do_fast;
    eval "require $loader_class" unless $loader_class->can('new');
    my $loader = $loader_class->new(-store=> $db,
				    -fast => $fast,
				    -index_subfeatures=>0,
	);
    $loader->start_load();
    $self->{loader}    = $loader;
    $self->{conflines} = [];
    $self->state('starting');
}

sub do_fast { 1 };

sub Loader {
    croak "The Loader() class method must be implemented in a subclass";
}

sub finish_load {
    my $self = shift;

    $self->set_status('creating database');
    $self->loader->finish_load();
    my $db        = $self->loader->store;
    my $conf      = $self->conf_fh;
    my $trackname = $self->track_name;
    my $dsn       = $self->dsn;
    my $backend   = $self->backend;

    my $trackno   = 0;
    my $loadid    = $self->loadid;
    $self->set_status('creating configuration');
    
    print $conf <<END;
[$loadid:database]
db_adaptor = Bio::DB::SeqFeature::Store
db_args    = -adaptor $backend
             -dsn     $dsn

#>>>>>>>>>> cut here <<<<<<<<
END

    if (my @lines = @{$self->{conflines}}) {  # good! user has provided some config hints
	my $in_sub;
	my ($old_trackname,$seen_feature);
	for my $line (@lines) {
	    chomp $line;
	    if ($line =~ /^\s*database/) {
		next;   # disallowed
	    }
	    elsif ($line =~ /^\[([^\]]+)\]/) { # overwrite track names to avoid collisions
		$old_trackname = $1;
		undef $seen_feature;
		my $trackname = $self->new_track_label;
		print $conf "[$trackname]\n";
		print $conf "database = $loadid\n" ;
		print $conf "category = My Tracks:Uploaded Tracks:",$self->track_name,"\n";
	    } elsif ($line =~ s/(=\s*)(sub .*)/$1 1 # no user subs allowed! $2/) {
		$in_sub++;
		print $conf $line,"\n";
	    } elsif ($in_sub && $line =~ /^\s+/) { # continuation line
		$line =~ s/^/# /;                  # continuation line of
		print $conf $line,"\n";
	    }
	    elsif ($line =~ /^feature/) {
		$seen_feature++;
		print $conf $line,"\n";
	    } elsif (!$line && $old_trackname && !$seen_feature) {
		print $conf "feature = $old_trackname\n\n";
		undef $old_trackname;
		undef $seen_feature;
	    } else {
		undef $in_sub;
		print $conf $line,"\n";
	    }
	}
	if ($old_trackname && !$seen_feature) {
	    print $conf "feature = $old_trackname\n\n";
	}
    } else {  # make something up
	my @types = eval {$db->toplevel_types};
	@types    = $db->types unless @types;

	my $filename = $self->track_name;
	for my $t (@types) {
	    my $trackname = $self->new_track_label($t);

	    my ($glyph,$stranded);
	    # start of a big heuristic section
	    if ($t =~ /gene|cds|exon|mRNA|transcript/i) {
		$glyph    = 'gene';
		$stranded = 0;
	    } else {
		$glyph    = 'segments';
		$stranded = 1;
	    }

	    my $color = $COLORS[rand @COLORS];
	    print $conf <<END;
[$trackname]
database = $loadid
feature   = $t
glyph     = $glyph
bgcolor   = $color
fgcolor   = black
label     = 1
stranded  = $stranded
connector = solid
balloon hover = \$description
category    = My Tracks:Uploaded Tracks:$filename
key         = $t

END
	}
    }
}

sub loader {shift->{loader}}
sub state {
    my $self = shift;
    my $d    = $self->{state};
    $self->{state} = shift if @_;
    $d;
}
sub load_line {
    my $self = shift;
    my $line = shift;

    my $old_state = $self->state;
    my $state     = $self->_state_transition($old_state,$line);

    if ($state eq 'data') {
	$self->loader->load_line($line);
    } elsif ($state eq 'config') {
	push @{$self->{conflines}},$line;
    } else {
	# ignore it
    }
    $self->state($state) if $state ne $old_state;
}

# shamelessly copied from Bio::Graphics:;FeatureFile.
sub _state_transition {
    my $self = shift;
    my ($current_state,$line) = @_;

    if ($current_state eq 'starting') {
	return $current_state unless /\S/;
	$current_state = 'config';
    }

    if ($current_state eq 'data') {
	return 'config' if $line =~ m/^\s*\[([^\]]+)\]/;  # start of a configuration section
    } 
    elsif ($current_state eq 'config') {
	return 'data'   if $line =~ /^\#\#(\w+)/;     # GFF3 meta instruction
	return 'data'   if $line =~ /^reference\s*=/; # feature-file reference sequence directive
	
	return 'config' if $line =~ /^\s*$/;                             #empty line
	return 'config' if $line =~ m/^\[([^\]]+)\]/;                    # section beginning
	return 'config' if $line =~ m/^[\w\s]+=/;                        # arg = value
	return 'config' if $line =~ m/^\s+(.+)/;                         # continuation line
	return 'config' if $line =~ /^\#/;                               # comment -not a meta
	return 'data';
    }
    return $current_state;
}
1;
