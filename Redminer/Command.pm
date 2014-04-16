package Redminer::Command;

use 5.010;
use Mouse;
use Data::Dumper;
use Getopt::Long;
use Encode qw/encode_utf8/;

use constant {
	OBJECT_PER_ITERATION => 30,
};

has engine => (
	is       => 'ro',
	isa      => 'WebService::Redmine',
	required => 1,
);

has args => (
	is       => 'ro',
	isa      => 'HashRef',
	required => 1,
	builder  => '_args',
);

around BUILDARGS => sub {
	my $orig  = shift;
	my $class = shift;

	my $_command = shift(@ARGV) // '';

	if (!length $_command) {
		die 'Empty command is not allowed';
	}

	my $command = ucfirst $_command;
	$command    =~ s/-([a-z])/uc $1/eg;

	eval "use Redminer::Command::$command";
	if ($@) {
		die "$_command is not implemented";
	}

	return $class->$orig(@_);
};

sub _args
{
	my $self = shift;
	my %args;

	if ($self->can('_args_spec')) {
		Getopt::Long::GetOptions(\%args, @{ $self->_args_spec });
	}

	if ($self->can('_args_defaults')) {
		my $defaults = $self->_args_defaults;
		foreach my $arg (keys %$defaults) {
			next if defined $args{$arg} || !defined $defaults->{$arg};
			$args{$arg} = $defaults->{$arg};
		}
	}

	return \%args;
}

sub run
{
	my $self = shift;
	my $rv   = $self->_run;

	if (!$rv) {
		$self->_log_engine_errors;
	}

	return $rv;
}

#
# Common routine for iterating over collections of objects
#
sub iterate
{
	my $self   = shift;
	my $what   = shift;
	my $cb     = shift;
	my $filter = shift // {};

	return ref $cb ne 'CODE';

	my $num_objects;
	
	$filter->{offset} = 0;
	$filter->{limit}  = OBJECT_PER_ITERATION;

	do {
		my $objects = $self->engine->$what($filter);
		last if !$objects;

		if (!defined $num_objects) {
			$num_objects = $objects->{total_count};
		}

		foreach my $object (@{ $objects->{$what} }) {
			&{$cb}($object);
		}

		$filter->{offset} += OBJECT_PER_ITERATION;
	} while ($filter->{offset} < $num_objects);

	return 1;
}

#
# Logging and error handling
#

sub log
{
	my $self    = shift;
	my $message = join("\n", map { ref($_)? Data::Dumper::Dumper($_) : $_ } @_);
	say $message;
	return 1;
}

sub _log_engine_errors
{
	my $self   = shift;
	my $errors = $self->engine->errorDetails;

	if (ref $errors ne 'HASH' || ref $errors->{errors} ne 'ARRAY') {
		return;
	}
	
	return $self->log('Following error(s) reported: ',
		map { sprintf "\t* %s", Encode::encode_utf8($_) } @{ $errors->{errors} }
	);
}

1;
