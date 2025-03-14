#!/usr/bin/perl
use strict;
use XML::Twig;
use utf8;
use Unicode::String;
use Parse::MediaWikiDump;
use Mysql;
use Switch;
use signatures;
use JavaScript;
use Slurp;
use JSON;
use Encode qw/encode decode/;
use MediaWiki::API;

#Connect to Mysql
mysqlcon '#p:localhost:piki:root:magda';
u 'DELETE FROM luthorword';

my $doPage = 1;

my @mod = qw/un le une aux des au de mi/;



my $file = $ARGV[0];

my $mw = MediaWiki::API->new();
$mw->{config}->{api_url} = 'http://fr.wiktionary.org/w/api.php';
$mw->login( { lgname => 'Arthurwolf', lgpassword => $ARGV[1] } ) || die $mw->{error}->{code} .': '. $mw->{error}->{details};

binmode(STDOUT, ':utf8');
my $pages = Parse::MediaWikiDump::Pages->new($file);
my $rt = JavaScript::Runtime->new();
my $script = slurp "lang/fr/extract.js";
$script = extendIncludes($script);
my $js = $rt->create_context();
$js->bind_function( nextPage => sub {
                        my $page = $pages->next();
                        $doPage = 0 unless $page;
                        return 0 unless $page;
                        my ( $word , $text ) = ( $page->title , $page->text );
                        $text = $$text;
                        
                        #Get word from site if it has been updated
                        if ( isIn(\@mod , $word) ) {
                            print "# OverWriting Word : $word\n";
                            my $page = $mw->get_page( { title => $word } );
                            $text = $page->{'*'};
                        }
                        
                        eval{ my $us = Unicode::String->new( $text  ); $text = $us->latin1() };
                        eval{ my $us = Unicode::String->new( $word  ); $word = $us->latin1() };                       
                        my $content = {
                            word     => $word,
                            content  => $text,
                            idWordExt => $page->id
                        };
                        #$content = extractWords( $content );
                        return $content;
                    } );
$js->bind_function( say      => sub { eval{my $words = join(" ",@_); print decode("UTF-8",$words), "\n"; } } );
$js->bind_function( wordAdd  => \&addWord );
$js->bind_function( 'system' => sub { my $cmd = join(" " , @_); return decode("UTF-8",`$cmd`); } );

#Now call the javascript to extract word information from the base
while ( $doPage ) {
    unless ( $js->eval( $script ) ){
        print "JSError : ", " " , $@, "\n";
        sleep 2;
    };
}


sub addWord{
    my ( $word ) = @_;
    my %a = %$word;
    $word = \%a;
    #javascript gives us crappy output
    foreach my $key ( %$word ) {
        eval{
        #$word->{$key} = decode("UTF-8",$word->{$key});
        }
    }

    my $wordword = $word->{word};
    $wordword =~ s/\s+/_/g;
    
    printf " %-3.3s | %-8.8s | %-25.25s | %-8.8s | %-3.3s | %-2.2s | %-1.1s | %-25.25s | %-2.2s\n", $word->{lang} , $word->{idWordExt} ,$wordword ,$word->{type} ,, $word->{gender} , $word->{number} , $word->{'verbNumber'} ,$word->{'verbTime'}  ;
    #Add to base
    u 'INSERT INTO luthorword ( idWordExt , word , type, gender, number, verbNumber, verbTime ) VALUES ( ?, ?, ?, ?, ?, ?, ? )' , $word->{idWordExt} , $wordword , $word->{type}, $word->{gender} , $word->{number} , $word->{'verbNumber'} ,$word->{'verbTime'} ;
}

sub extractWords{
    my ( $content ) = @_;
    my @fields = split(/(?=\{\{\-((?:.*?)\-(?:.*?))\}\})/s,$content->{content});
    my @words;
    for (@fields) {
        my $con = $_;
        if ( $con =~ m/^\{\{\-(.+?)\-\|(.+?)\}\}/ ) {
            my ( $type , $lang ) = ( $1 , $2 );
            #next if $lang !~ m/fr/;
            #next if $type eq "flex-verb";
            #next if $type !~ /^(nom|adj|verb)$/;
            my $word = {
                word        => $content->{word},
                idWordExt   => $content->{idWordExt},
                'type'      => $type,
                'content'   => $con,
                'lang'      => $lang,
            };
            push @words , $word;
        }
    }
    $content->{"words"} = \@words;
    return $content;
}


sub isIn{
    my ( $array , $value ) = @_;
    for ( @$array ) {
        return 1 if $value eq $_;
    }
    return 0;
}


sub extendIncludes{
    my ($script) = @_;
    my $ret;
    for ( split("\n",$script) ) {
        my $line = $_;
        if ( $line =~ m/^\#include (.*)$/ ) {
            my $filename = $1;
            my $toAdd = slurp $filename;
            $toAdd = extendIncludes( $toAdd );
            $ret .= $toAdd . "\n";
        }else {
            $ret .= $line . "\n";
        }
    }
    return $ret;
}
