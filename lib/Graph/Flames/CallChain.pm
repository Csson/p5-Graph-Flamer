use 5.20.0;
use warnings;

package Graph::Flames::CallChain;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use Moo;
use Types::Standard -all;
use List::Util qw/first max/;
use experimental qw/postderef signatures/;

has name => (
    is => 'rw',
    isa => Str,
    required => 1,
);
has total_ticks => (
    is => 'rw',
    isa => Num,
    required => 1,
);
has depth => (
    is => 'ro',
    isa => Int,
    required => 1,
);
has children => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['Graph::Flames::CallChain']],
    default => sub { [] },
);


sub add_to_ticks($self, $ticks) {
    $self->total_ticks($self->total_ticks + $ticks);
}
sub add_stack($self, $stack, $at) {
    $self->add_to_ticks($stack->ticks);

    my $current_name = $stack->calls->[$at];
    my $child = $self->find_child_by_name($current_name);
    my $stuff = 0;
    if($child) {
        $child->add_stack($stack, ++$at);
    }
    else {
        push $self->children->@* => Graph::Flames::CallChain->new(name => $current_name, total_ticks => $stack->ticks, depth => $self->depth + 1);
    }
}
sub find_child_by_name($self, $name) {
    return first { $_->name eq $name } $self->children->@*;
}
sub find_max_depth($self) {
    return $self->depth if !scalar $self->children->@*;
    return max(map { $_->find_max_depth } $self->children->@*);
}

1;
