package Alien::Base::ModuleBuild::Repository::HTTP;

use strict;
use warnings;

our $VERSION = '0.001_003';
$VERSION = eval $VERSION;

use Carp;

use Class::Load qw( load_class );
use File::Basename qw( basename );
use HTTP::Tiny;
use Scalar::Util qw( blessed );
use URI;

use Alien::Base::ModuleBuild::Utils;

use parent 'Alien::Base::ModuleBuild::Repository';

our $Has_HTML_Parser = eval { require HTML::LinkExtor; 1 };

sub connection {

  my $self = shift;

  return $self->{connection}
    if $self->{connection};

  # allow easy use of HTTP::Tiny subclass
  $self->{protocol_class} ||= 'HTTP::Tiny';
  load_class( $self->{protocol_class} );

  my $http = $self->{protocol_class}->new();
  if ( $self->{env_proxy} ) {
    $http->env_proxy;
  }

  $self->{connection} = $http;

  return $http;

}

sub get_file {
  my $self = shift;
  my $url = shift || croak "Must specify url to download";

  my $file = basename( $url );
  my $res = $self->connection->mirror($url, $file);
  my ( $is_error, $content ) = $self->check_http_response( $res );
  croak "Download failed: " . $content . " ($url)" if $is_error;

  return 1;
}

sub list_files {
  my $self = shift;

  my $host = $self->host;
  my $location = $self->location;
  my $uri = URI->new('http://' . $host . $location);

  my $res = $self->connection->get($uri);

  my ( $is_error, $content ) = $self->check_http_response( $res );
  if ( $is_error ) {
    carp $content;
    return ();
  }

  my @links = $self->find_links($content);

  return @links;  
}

sub find_links {
  my $self = shift;
  my ($html) = @_;

  my @links;
  if ($Has_HTML_Parser) {
    push @links, $self->find_links_preferred($html) 
  } else {
    push @links, $self->find_links_textbalanced($html)
  }

  return @links;
}

sub find_links_preferred {
  my $self = shift;
  my ($html) = @_;

  my @links;

  my $extor = HTML::LinkExtor->new(
    sub { 
      my ($tag, %attrs) = @_;
      return unless $tag eq 'a';
      return unless defined $attrs{href};
      push @links, $attrs{href};
    },
  );

  $extor->parse($html);

  return @links;
}

sub find_links_textbalanced {
  my $self = shift;
  my ($html) = @_;
  return Alien::Base::ModuleBuild::Utils::find_anchor_targets($html);
}

sub check_http_response {
  my ( $self, $res ) = @_;
  if ( blessed $res && $res->isa( 'HTTP::Response' ) ) {
    if ( !$res->is_success ) {
      return ( 1, $res->status_line . " " . $res->decoded_content );
    }
    return ( 0, $res->decoded_content );
  }
  else {
    if ( !$res->{success} ) {
      return ( 1, $res->{reason} );
    }
    return ( 0, $res->{content } );
  }
}

1;

