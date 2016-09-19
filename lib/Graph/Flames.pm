use 5.20.0;
use warnings;

package Graph::Flames;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use utf8;
use Moo;
use Types::Standard -all;
use SVG;
use Data::Printer;
use List::Util qw/sum any uniq none/;
use Number::Format qw/format_number/;
use Convert::AnyBase;
use Graph::Flames::CallStack;
use Graph::Flames::CallChain;
use experimental qw/postderef signatures/;

has callstacks => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['Graph::Flames::CallStack']],
    required => 1,
);
has ticks_per_second => (
    is => 'ro',
    isa => Int,
    required => 1,
);
has total_time => (
    is => 'ro',
    isa => Num,
    predicate => 1,
);

has flame_config => (
    is => 'ro',
    isa => HashRef,
    default => sub {
        return +{
            depth_height => 18,
            font_width => 8,
        };
    }
);

has svg_config => (
    is => 'ro',
    isa => HashRef,
    default => sub {
        return +{
            width => 1200,
            -inline => 1,
            -nocredits => 1,
            -indent => '',
        };
    }
);
#---
has subnames => (
    is => 'ro',
    isa => ArrayRef,
    lazy => 1,
    builder => 1,
);
sub _build_subnames($self) {
    return [uniq map { $_->calls->@* } $self->callstacks->@*];
}

has color_class => (
    is => 'ro',
    isa => HashRef,
    lazy => 1,
    builder => 1,
);
sub _build_color_class($self) {
    my @short_sub_names = uniq map { substr $_, 0, 15 } $self->subnames->@*;
    my $names;
    $names->{ $_ }{'group'} = $self->calculate_name_color_group($_) for @short_sub_names;

    my $groups;
    for my $name (keys $names->%*) {
        my $group = $names->{ $name }{'group'};
        $groups->{ $group } = [] if !exists $groups->{ $group };
        push $groups->{ $group }->@*, $name;
    }
    my @sorted_groups = sort { scalar $groups->{ $b }->@* <=> scalar $groups->{ $a }->@* } keys $groups->%*;

    my $color_id = 1;
    for my $groupkey (@sorted_groups) {

        for my $name ($groups->{ $groupkey }->@*) {
            $names->{ $name }{'class'} = "c-$color_id";
        }
        $color_id += 1 if $color_id < 8;
    }

    return $names;
}
sub color_class_for_name($self, $name) {
    $name = substr $name, 0, 15;
    return 'c-bar' if !$self->color_class->{ $name }{'class'};
    return $self->color_class->{ $name }{'class'};
}
has total_ticks => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => sub($self) {
        return $self->has_total_time
             ? int($self->total_time * $self->ticks_per_second)
             : sum(map { $_->ticks } $self->callstacks->@*)
             ;
    }
);

has callchain => (
    is => 'ro',
    isa => InstanceOf['Graph::Flames::CallChain'],
    lazy => 1,
    builder => 1,
);
sub _build_callchain($self) {
    my @shortest_stacks_first = sort { scalar $a->calls->@* <=> $b->calls->@* || $a->calls->[-1] cmp $b->calls->[-1] } $self->callstacks->@*;

    my $root = Graph::Flames::CallChain->new(name => '', total_ticks => 0, depth => 1);

    for my $stack (@shortest_stacks_first) {
        $root->add_stack($stack, 0);
    }
    if($self->has_total_time && $self->total_time * $self->ticks_per_second > $root->total_ticks) {
        $root->total_ticks($root->total_ticks + int($self->total_time * $self->ticks_per_second) - $root->total_ticks);
    }
    return $root;
}
has max_depth => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => sub($self) {
        $self->callchain->find_max_depth;
    }
);
has ticks_per_pixel => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => sub($self) {
        $self->callchain->total_ticks / $self->svg_config->{'width'};
    },
);
has svg => (
    is => 'ro',
    isa => InstanceOf['SVG'],
    lazy => 1,
    builder => 1,
);
has converter => (
    is => 'ro',
    isa => Any,
    lazy => 1,
    builder => 1,
);
sub _build_converter($self) {
    Convert::AnyBase->new(set => join '', (0..9, 'a'..'z', 'A'..'Z'));
}

sub _build_svg($self) {

    my $svg = SVG->new(
        $self->svg_config->%*,
        height => (2 + $self->max_depth) * $self->flame_config->{'depth_height'},
        'data-font-width' => $self->flame_config->{'font_width'},
        'data-ticks-per-second' => $self->ticks_per_second,
    );
    $svg->g(id => 'search-results');

    # put all chains in a <g> -> saves setting a css class
    my $chaing = $svg->g(id => 'chains');
    my $x = $self->svg_config->{'width'};
    my $y = (2 + $self->max_depth) * $self->flame_config->{'depth_height'} - $self->flame_config->{'depth_height'};


    $self->draw($svg, $self->callchain, $x, $y);
    return $svg;
}

# $x is the *right* hand x..
sub draw($self, $svg, $chain, $x, $y) {
    my $width = sprintf '%.3f' => $chain->total_ticks / $self->ticks_per_pixel;
    my $seconds = $chain->total_ticks / $self->ticks_per_second;
    my $percent = sprintf '%.2f' => $chain->total_ticks / $self->total_ticks * 100;
    my $ms = format_number(int($seconds * 1_000_000));
    my @classes = ('chain', ($self->color_class_for_name($chain->name) || 'chain color-0'));
    push @classes => 'zoom-too-thin' if $width < 0.1;
    my $id = 's-'.$self->converter->encode($stack_ids->[-1]);
    push @classes => map { 's-'.$self->converter->encode($_) } $stack_ids->@*;

    my $g = $svg->tag(g =>
        class => join (' ' => @classes),
        'data-ticks' => $chain->total_ticks,
        'data-ms' => $ms,
        'data-percent' => $percent,
        'data-name' => $chain->name,
    );
    $g->title(-cdata => sprintf '%s (%s microseconds, %s%%)', $chain->name, $ms, $percent);

    $g->rectangle(x => $x - $width,
                  y => $y,
                  width => $width,
                  height => $self->flame_config->{'depth_height'},
                  rx => 2,
                  ry => 2,
    );

    my $max_text_length = int ($width / $self->flame_config->{'font_width'});
    my $text = length $chain->name > $max_text_length ? $max_text_length >= 3 ? substr($chain->name, 0, $max_text_length - 1) . '…'
                                                      :                         undef
             :                                          $chain->name
             ;

    # only create <text> tags for blobs with visible text, the rest will fetch them from the first one that got it (see above)
    if(defined $text) {
        $g->text(x => $x - $width + 2.5,
                 y => $y + 13,
                 -cdata => $text,
        );
    }

    my $child_x = $x;
    my $child_y = $y - $self->flame_config->{'depth_height'};
    for my $child (sort { $b->name cmp $a->name } $chain->children->@*) {
        $child_x -= $self->draw($svg, $child, $child_x, $y = $child_y - 1);
    }
    return $width;
}
# borrowed from flamegraph.pl
sub calculate_name_color_group($self, $name) {
    my $vector = 0;
    my $weight = 1;
    my $max = 1;
    my $mod = 10;

    foreach my $char (split //, $name) {
        my $i = ord($char) % $mod;
        $vector += ($i / ($mod++ - 1)) * $weight;
        $max += 1 * $weight;
        $weight *= .85;
        last if $mod > 13;
    }
    return sprintf '%.2f' => 1 - $vector / $max;

}

1;
