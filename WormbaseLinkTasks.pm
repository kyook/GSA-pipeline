package WormbaseLinkTasks;

use strict;
use TextpressoGeneralTasks;
use WormbaseLinkGlobals;
use GeneralTasks;
use GeneralGlobals;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(findAndLinkObjects 
                 getStopWords 
                 loadLexicon 
                 formEntityTable
                 getWbPaperId 
                 getAuthorObjects 
                 getSender 
                 getReceivers
                );

sub findAndLinkObjects {
    my $xml                = shift;
    my $tok_txt            = shift;
    my $lexicon_ref        = shift;
    my $sorted_entries_ref = shift;
    my $wbpaper_id         = shift;
    my $xml_format         = shift;
    my $gsa_id             = shift;

    print "Linking begins now...\n";

    my $linked_xml = $xml;

    # hash used for avoiding sub-string matches
    my %orig = (); # key: hidden name, value: entity

    for my $entity_name (@$sorted_entries_ref) {

        # matching happens in $tok_txt; links added to $linked_xml
        if ($tok_txt =~ /\Q$entity_name\E/) { 

            my $class = get_entity_class( keys %{$lexicon_ref->{$entity_name}} );

            # generic URL; is changed for special cases below.
            my $url = "http://www.wormbase.org/db/get?name=$entity_name;class=$class";

            # skip what won't be linked
            if ( $class eq "Gene" || $class eq "Protein" ) {
                next if ($linked_xml !~ /\b(\Q$entity_name\E)(p?)\b/);
            }
            else {
                next if ($linked_xml !~ /\b\Q$entity_name\E\b/);
            }
            
            print "$class \'$entity_name\'\n"; 

            if ( $class eq "Gene" || $class eq "Protein" ) {
                $url = "http://www.wormbase.org/db/get?name=$entity_name;class=Gene";

                # hide matched entity to avoid future sub-string matches
                # Hidden entities are replaced with originals once matching is done.
                $linked_xml = link_entity_in_xml($linked_xml, $entity_name, $url, \%orig);

                # if there is a 'p' after gene name, link it to the gene
                $entity_name .= 'p';
                $linked_xml = link_entity_in_xml($linked_xml, $entity_name, $url, \%orig);
            } 
            
            elsif (    $class eq "Strain"
                    || $class eq "Clone"
                    || $class eq "Transgene"
                    || $class eq "Rearrangement"
                    || $class eq "Sequence"
#                    || $class eq "Anatomy_term"
#                    || $class eq "Anatomy_name"
            ) {
                $linked_xml = link_entity_in_xml($linked_xml, $entity_name, $url, \%orig);
            }
            
            elsif ($class eq "Variation") {
                my $allele_root = removeAlleleSuffix($entity_name);
                $url = "http://www.wormbase.org/db/get?name=$allele_root;class=$class";
                $linked_xml = link_variation_in_xml($linked_xml, $entity_name, $allele_root, $url, \%orig);
            }
            
            elsif ($class eq "Phenotype") {
                my $phenotype_id = $lexicon_ref->{$entity_name}{$class}; 
                $url = "http://www.wormbase.org/db/get?name=$phenotype_id;class=$class";
                $linked_xml = link_entity_in_xml($linked_xml, $entity_name, $url, \%orig);
            }
        }

        # special case for Variation. entries like snp_2L52[1]
        elsif ($entity_name =~ /^snp_/) {
            if ($tok_txt =~ /($entity_name)/i) {
                for my $class (keys %{$lexicon_ref->{$entity_name}}) { # only Variation here.
                    
                    print "$class \'$entity_name\' (special case for Variation)\n";

                    my $allele_root = removeAlleleSuffix($entity_name);
                    my $url = "http://www.wormbase.org/db/get?name=$allele_root;class=Variation";
                    
                    $linked_xml = link_variation_in_xml($linked_xml, $entity_name, $allele_root, $url, \%orig);
                }
            }
        }
        
        $tok_txt =~ s/\Q$entity_name\E/ /g;
    }

    $linked_xml = linkSpecialCasesUsingPatternMatch($linked_xml, $lexicon_ref, \%orig);

    $linked_xml = GeneralTasks::replace_hidden_entities($linked_xml, \%orig);

# upon Karen's request from 04/10/12 don't do any author linking for now.
#    $linked_xml = linkAuthorNames($linked_xml, $wbpaper_id, $xml_format);

    $linked_xml = removeUnwantedLinks($linked_xml, $xml_format);

    $linked_xml = escape_urls( $linked_xml );

    die "FATAL ERROR: XML text changed during linking!\n"
        if ( ! original_txt_is_preserved($xml, $linked_xml, $gsa_id) );

    $linked_xml = GeneralTasks::highlight_text( $linked_xml );

    return $linked_xml;
}

sub link_entity_in_xml {
    my $xml      = shift;
    my $entity   = shift;
    my $url      = shift;
    my $orig_ref = shift;

    my $hidden_entity = GeneralTasks::get_hidden_entity( $entity, $orig_ref );
    (my $hidden_url = $url) =~ s/\Q$entity\E/$hidden_entity/;
    
    my $jsid = 1;
    foreach ($xml =~ /\b\Q$entity\E\b/g) {
        my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                  . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                  . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                  . "</a>";
    
        $xml =~ s/\b\Q$entity\E\b/$repl/;

        $jsid++;
    }

    return $xml;
}

sub link_variation_in_xml {
    my $xml         = shift;
    my $entity      = shift;
    my $name_in_url = shift;
    my $url         = shift;
    my $orig_ref    = shift;

    my $hidden_name_in_url = GeneralTasks::get_hidden_entity( $name_in_url, $orig_ref );
    (my $hidden_url = $url) =~ s/$name_in_url/$hidden_name_in_url/;
    
    my $hidden_entity = GeneralTasks::get_hidden_entity( $entity, $orig_ref );

    my $jsid = 1;
    foreach ($xml =~ /\b$entity\b/g) {
        my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                  . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                  . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                  . "</a>";
    
        $xml =~ s/\b$entity\b/$repl/;

        $jsid++;
    }

    return $xml;
}

sub escape_urls {
    my $xml = shift;

    use URI::Escape;

    my $xmlcopy = $xml;
    while ($xmlcopy =~ m{"http://www\.wormbase\.org/db/get\?name=(.+?);class=.+?"}g) {
        my $name_in_link = $1;
        my $esc_name = uri_escape( $name_in_link );
        if ($esc_name ne $name_in_link) {
            $xml =~ s{"(http://www\.wormbase\.org/db/get\?name=)$name_in_link(;class=.+?)"}{"$1$esc_name$2"}g;
        }

        $xmlcopy =~ s{"http://www\.wormbase\.org/db/get\?name=$name_in_link;class=.+?"}{ }g;
    }

    return $xml;
}

sub linkAuthorNames {
    my $xml = shift;
    my $wbpaper_id = shift;
    my $xml_format = shift;

    my $ret = "";
    if ($xml_format eq FLAT_XML_ID) {
        $ret = linkAuthorNamesFlatXml($xml, $wbpaper_id);
    } elsif ($xml_format eq NLM_XML_ID) {
        $ret = linkAuthorNamesNlmXml($xml, $wbpaper_id);
    }

    return $ret;
}

sub linkAuthorNamesNlmXml {
    my $xml = shift;
    my $wbpaper_id = shift;

    my $xmlcopy = $xml;

    print "Linking author names...\n\n";
    while ($xmlcopy =~ /<contrib contrib-type="author"( corresp="yes")?><name><surname>(.+?)<\/surname><given-names>(.+?)<\/given-names>/g) {
        my $surname = $2;
        my $given_names = $3;
        my $full_name = "$given_names $surname";
        print "fullname = $full_name\n";
        
        my $url_encoded_name = uri_escape($full_name);
        $url_encoded_name =~ s/\.//g; # WormBase does not have the aliases with a period after middle name!
        my $url = "http://www.wormbase.org/db/misc/person?name=$url_encoded_name;paper=$wbpaper_id";
        print "url = $url\n\n";

        # $xml =~ s/(<contrib contrib-type="author"( corresp="yes")?><name><surname>$surname<\/surname><given-names>$given_names<\/given-names><\/name>)/$1<ext-link ext-link-type="uri" xlink:href="$url"\/>/;
        $xml =~ s/<contrib contrib-type="author"( corresp="yes")?><name><surname>$surname<\/surname><given-names>$given_names<\/given-names><\/name>/<contrib contrib-type="author"$1><name><surname><a href="$url">$surname<\/a><\/surname><given-names><a href="$url">$given_names<\/a><\/given-names><\/name>/;
    }

    return $xml;
}

sub linkAuthorNamesFlatXml {
    my $xml = shift;
    my $wbpaper_id = shift;

    $xml =~ /\<Authors\>(.+)\<\/Authors\>/;
    my $author_names = $1; # <au_fname>Feifan</au_fname> <au_surname>Zhang</au_surname>, 
    # <au_fname>M. Maggie</au_fname> <au_surname>O&#x2019;Meara</au_surname>, and 
    # <au_fname>Oliver</au_fname> <au_surname>Hobert</au_surname><cite_fn><SUP>1</SUP></cite_fn> 
    
    while ($author_names =~ /<au_fname>(.+?)<\/au_fname> <au_surname>(.+?)<\/au_surname>/g) {
        my $firstname = $1;
        my $lastname  = $2;

        my $clean_lastname = $lastname;
        $clean_lastname =~ s/\,$//; # DJS keeps commas inside the tags sometimes!

        my $clean_firstname = $firstname;
        $clean_firstname =~ s/\.//g; # WB does not have period in first or middle names 

        my $fullname  = "$clean_firstname $clean_lastname";
        my $url_encoded_name = uri_escape($fullname);
        my $url = "http://www.wormbase.org/db/misc/person?name=$url_encoded_name;paper=$wbpaper_id";

        $xml =~ s/<au_fname>$firstname<\/au_fname> <au_surname>$lastname<\/au_surname>/<au_fname><a href="$url">$firstname<\/a><\/au_fname> <au_surname><a href="$url">$lastname<\/a><\/au_surname>/;
    }

    return $xml;
}

sub linkAuthorNamesFlatXmlOld {
    my $xml = shift;
    my $wbpaper_id = shift;

    $xml =~ /\<Authors\>(.+)\<\/Authors\>/;
    my $author_names = $1; # Meredith J. Ezak,* Elizabeth Hong,<SUP>1</SUP> Angela Chaparro-Garcia<SUP>1,2</SUP> and Denise M. Ferkey<SUP>3</SUP>
    # Sumeet Sarin,* Vincent Bertrand,* Henry Bigelow,*<SUP>,&#x2020;</SUP> Alexander Boyanov,* Maria Doitsidou,* Richard Poole,* Surinder Narula* 
    # and Oliver Hobert*
    
    # remove all XML <SUP> tags and their contents
    $author_names =~ s/\<SUP\>.+?\<\/SUP\>//g; # Meredith J. Ezak, Elizabeth Hong, Angela Chaparro-Garcia and Denise M. Ferkey

    # remove all the asterisks
    $author_names =~ s/\*//g;

    # remove other tags like <B>, <I>, etc.,
    $author_names =~ s/\<\/?.+?\>//g;

    my @entries = split (/\,\s+/, $author_names);
    my $last_two_names = pop @entries;
    (my $author_1, my $author_2) = split(/ and /, $last_two_names);
    if ( ($author_1 =~ /\S/) && ($author_2 =~ /\S/) ) { # needed since sometimes there is no 'and' at the end!
        push @entries, $author_1;
        push @entries, $author_2;
    } else { # put the last fullname back
        push @entries, $last_two_names;
    }

    print "Author names\n";
    for my $fullname (@entries) {
        my $url_encoded_name = uri_escape($fullname);
        $url_encoded_name =~ s/\.//g; # WormBase does not have the aliases with a period after middle name!
        my $url = "http\:\/\/www\.wormbase\.org\/db\/misc\/person\?name=$url_encoded_name\;paper=$wbpaper_id";

        # this is for DJS; middle initial is part of first name
        my @subnames = split(/\s/, $fullname);
        my $last_name = pop @subnames;
        my $first_name = join(" ", @subnames);
        print "first_name = $first_name\n";
        print "last_name  = $last_name\n";
        
        $xml =~ s/$fullname/\<a href=\"$url\"\>$first_name\<\/a\> \<a href=\"$url\"\>$last_name\<\/a\>/g;
    }
    return $xml;
}

# use URI::Escape escape_uri Perl built-in
#sub encodeInHtml {
#    my $string = shift;
#
#    $string =~ s/ /\%20/g;
#    $string =~ s/'/\%27/g;
#    $string =~ s/\:/\%3A/g;
#    $string =~ s/\Q&#x00E9;\E/e/g; # e with an accent - occurs in author names
#    $string =~ s/\Q&#x2019;\E/\%27/g; # single quote
#
#    return $string;
#}

sub removeAlleleSuffix {
    my $entity_name = shift;
    
    my $root = $entity_name;
    for my $suffix ( @{(WormbaseLinkGlobals::SY_ALLELE_SUFFIXES)} ) {
        if ($entity_name =~ /^(.+)$suffix$/) {
            $root = $1;
            last;
        }
    }
    return $root;
}

sub linkSpecialCasesUsingPatternMatch {
    print "\n** Linking special cases **\n";
    my $xml = shift;
    my $lexicon_ref = shift;
    my $orig_ref = shift;

    $xml = linkSpecialVariationsUsingPatternMatch($xml, $lexicon_ref, $orig_ref);
    $xml = linkSpecialGenesUsingPatternMatch($xml, $lexicon_ref, $orig_ref);
    return $xml;
}

sub linkSpecialGenesUsingPatternMatch {
    my $xml         = shift;
    my $lexicon_ref = shift;
    my $orig_ref    = shift;

    # link transgenes like sdf-9V to sdf-9 gene page
    while ($xml =~ /\b([a-z]{1,4}-\d+)(p|V)\b/g) { 
        my $gene = $1;
        my $suff = $2;

        next if (! defined( $lexicon_ref->{$gene}{"Gene"} ));

        my $url = "http://www.wormbase.org/db/get?name=$gene;class=Gene";
        #$xml =~ s/\b($gene$suff)\b/\<a href=\"$url\"\>$1\<\/a\>/g;
        $xml = link_entity_in_xml( $xml, 
                                   $gene . $suff,
                                   $url,
                                   $orig_ref
                                 );
    }

    # link double mutant genes with no delimiters. eg: osm-9ocr-2
    while ($xml =~ /\b([a-zA-Z]{3,4}-\d+)([a-zA-Z]{3,4}-\d+)\b/g) { 
        my ($gene1, $gene2) = ($1, $2);
        
        my $url1; 
        if ( defined($lexicon_ref->{$gene1}{"Gene"}) ) { 
            $url1 = "http://www.wormbase.org/db/get?name=$gene1;class=Gene";
        }

        my $url2;
        if ( defined($lexicon_ref->{$gene2}{"Gene"}) ) {
            $url2 = "http://www.wormbase.org/db/get?name=$gene2;class=Gene";
        }

        if ($url1 && $url2) {
            print "Linking $gene1$gene2\n";
            
            my $hidden_entity = GeneralTasks::get_hidden_entity( $gene1, $orig_ref );
            (my $hidden_url = $url1) =~ s/\Q$gene1\E/$hidden_entity/;
            my $jsid = 1;
            foreach ($xml =~ /\b\Q$gene1\E/g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xml =~ s/\b\Q$gene1$gene2\E\b/$repl$gene2/;
                $jsid++;
            }

            $hidden_entity = GeneralTasks::get_hidden_entity( $gene2, $orig_ref );
            ($hidden_url = $url2) =~ s/\Q$gene2\E/$hidden_entity/;
            $jsid = 1;
            foreach ($xml =~ m{</a>\Q$gene2\E\b}g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xml =~ s{</a>\Q$gene2\E\b}{</a>$repl};
                $jsid++;
            }

        } 
        elsif ($url1) {
            print "Linking $gene1\n";
            my $hidden_entity = GeneralTasks::get_hidden_entity( $gene1, $orig_ref );
            (my $hidden_url = $url1) =~ s/\Q$gene1\E/$hidden_entity/;
            my $jsid = 1;
            foreach ($xml =~ /\b\Q$gene1\E/g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xml =~ s/\b\Q$gene1$gene2\E\b/$repl$gene2/;
                $jsid++;
            }
        } 
        elsif ($url2) { 
            print "Linking $gene2\n";
            my $hidden_entity = GeneralTasks::get_hidden_entity( $gene2, $orig_ref );
            (my $hidden_url = $url2) =~ s/\Q$gene2\E/$hidden_entity/;
            my $jsid = 1;
            foreach ($xml =~ m{\b\Q$gene1$gene2\E\b}g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xml =~ s{\b\Q$gene1$gene2\E\b}{$gene1$repl};
                $jsid++;
            }
        }
    }

    # link the 11 part in RGS-10/11 to RGS-11 gene page
    # link the -2 part in ZIM-1, -2 to ZIM-2 page
    my $xmlcopy = $xml;
    while ($xml =~ m{((<a href=\S+?;class=Gene" \S+?>(\S+?)</a><a \S+?><sup><img \S+?></sup></a>)(/|, |; )(-?)(\d+))}g) {
        my $full_expression    = $1; # <a href="http://www.wormbase.org/db/get?name=RGS-10;class=Gene">RGS-10</a>/11 
        my $linked_first_part  = $2; # <a href="http://www.wormbase.org/db/get?name=RGS-10;class=Gene">RGS-10</a>
        my $hidden_first_gene  = $3; # RGS-10
        my $separator          = $4; # / or comma followed by space
        my $hyphen             = $5; # not defined in RGS-10/11 example
        my $second_gene_number = $6; # 11

        my $first_gene = $orig_ref->{ $hidden_first_gene };

        print "Matched full expression = $full_expression\n";
        print "Linked first part       = $linked_first_part\n";
        print "first gene              = $first_gene\n";
        print "second genenumber       = $second_gene_number\n";
        
        (my $gene_prefix = $first_gene) =~ s/\d+//;
        my $second_gene = $gene_prefix . $second_gene_number;
        print "Second gene             = $second_gene\n";
        my $new_url = "http://www.wormbase.org/db/get?name=$second_gene;class=Gene";
        
        if ($hyphen) {
            print "Linking \'$hyphen$second_gene_number\' in $full_expression to $new_url\n";
            $xmlcopy =~ s{\Q$full_expression\E}
                        {$linked_first_part$separator<a href="$new_url">$hyphen$second_gene_number</a>};
        } else {
            #open (OUT, ">temp");
            #print OUT "$xml";
            #close (OUT);
            print "Linking \'$second_gene_number\' in $full_expression to $new_url\n";
            $xmlcopy =~ s{\Q$full_expression\E}
                         {$linked_first_part$separator<a href="$new_url">$second_gene_number</a>};
            #open (OUT, ">temp2");
            #print OUT "$xml";
            #close (OUT);
        }
    }

    # $xml = TextpressoGeneralTasks::ReplaceSpecChar($xml);
        
    return $xmlcopy;
}

sub linkSpecialVariationsUsingPatternMatch {
    # cis double mutant case (like zu405te33)
    my $xml = shift;
    my $lexicon_ref = shift;
    my $orig_ref = shift;

    my %already_linked = ();
    my $xmlcopy = $xml;
    while ($xml =~ /\b([a-z]{1,3}\d+)([a-z]{1,3}\d+)\b/g) {
        my ($var1, $var2) = ($1, $2);
        if ( defined( $already_linked{$var1}{$var2} ) ) {
            next;
        }
        else {
            $already_linked{$var1}{$var2} = 1;
        }
             
        print "variation (caught with pattern match): $var1$var2\n";
        
        my $url1;
        my $url2;
        $url1 = "http://www.wormbase.org/db/get?name=$var1;class=Variation" 
            if ( defined($lexicon_ref->{$var1}{"Variation"}) );
        $url2 = "http://www.wormbase.org/db/get?name=$var2;class=Variation" 
            if ( defined($lexicon_ref->{$var2}{"Variation"}) );

        if ($url1 && $url2) {
            print "Linking $var1$var2\n";
            
            my $hidden_entity = GeneralTasks::get_hidden_entity( $var1, $orig_ref );
            (my $hidden_url = $url1) =~ s/\Q$var1\E/$hidden_entity/;
            my $jsid = 1;
            foreach ($xml =~ /\b\Q$var1\E/g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xmlcopy =~ s/\b\Q$var1$var2\E\b/$repl$var2/;
                $jsid++;
            }

            $hidden_entity = GeneralTasks::get_hidden_entity( $var2, $orig_ref );
            ($hidden_url = $url2) =~ s/\Q$var2\E/$hidden_entity/;
            $jsid = 1;
            foreach ($xml =~ m{</a>\Q$var2\E\b}g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xmlcopy =~ s{</a>\Q$var2\E\b}{</a>$repl};
                $jsid++;
            }
        } 
        elsif ($url1) {
            print "Linking $var1\n";
            my $hidden_entity = GeneralTasks::get_hidden_entity( $var1, $orig_ref );
            (my $hidden_url = $url1) =~ s/\Q$var1\E/$hidden_entity/;
            my $jsid = 1;
            foreach ($xml =~ /\b\Q$var1\E/g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xmlcopy =~ s/\b\Q$var1$var2\E\b/$repl$var2/;
                $jsid++;
            }
        } 
        elsif ($url2) {
            print "Linking $var2\n";
            my $hidden_entity = GeneralTasks::get_hidden_entity( $var2, $orig_ref );
            (my $hidden_url = $url2) =~ s/\Q$var2\E/$hidden_entity/;
            my $jsid = 1;
            foreach ($xml =~ m{\b\Q$var1$var2\E\b}g) {
                my $repl =  "<a href=\"$hidden_url\" id=\"$hidden_entity-$jsid\">$hidden_entity</a>"
                          . "<a href=\"javascript:removeLinkAfterConfirm('$hidden_entity-$jsid')\">"
                          . "<sup><img src=\"/gsa/img/minus.png\"/></sup>"
                          . "</a>";
                $xmlcopy =~ s{\b\Q$var1$var2\E\b}{$var1$repl};
                $jsid++;
            }
        }
    }

    return $xmlcopy;
}

sub linkVariationUsingPatternMatch {
    my $xml = shift;
    my $entity_name = shift;
    my $lexicon_ref = shift;
    
    if ($entity_name =~ /([a-z]{1,3}\d+)([a-z]{1,3}\d+)/) {
	    my $part1 = $1;
    	my $part2 = $2;
	    if (defined($lexicon_ref->{$part2}{"Variation"})) { # entries like ct46ct101 need to be linked to ct46 and ct101 pages
	        my $url1 = "http://www.wormbase.org/db/get?name=$part1;class=Variation";
	        my $url2 = "http://www.wormbase.org/db/get?name=$part2;class=Variation";
	        $xml =~ s/\b($part1)($part2)\b/<a href=\"$url1\">$1<\/a><a href=\"$url2\">$2<\/a>/g;
    	} 
        else {
	        my $url = "http://www.wormbase.org/db/get?name=$part1;class=Variation";
	        $xml =~ s/\b($entity_name)\b/<a href=\"$url\">$1<\/a>/g;
    	}
    } elsif ($entity_name =~ /([a-z]{1,3}\d+)(\w*)$/) { # link entries like ad450sd to ad450 page
	    my $url = "http://www.wormbase.org/db\/get?name=$1;class=Variation";
    	$xml =~ s/\b($entity_name)\b/<a href=\"$url\">$1<\/a>/g;
    }
    
    return $xml;
}


sub removeUnwantedLinks {
    my $xml = shift;
    my $xml_format = shift;
    
    my $ret = "";
    if ($xml_format eq FLAT_XML_ID) {
        $ret = removeUnwantedLinksFlatXml($xml);
    } elsif ($xml_format eq NLM_XML_ID) {
        $ret = removeUnwantedLinksNlmXml($xml);
    }

    return $ret;
}

sub removeUnwantedLinksNlmXml {
    my $xml = shift;

    $xml = GeneralTasks::removeLinksInAcknowledgments( $xml );

    # remove any links in query comments like 
    # <!-- Q1 -->
    # <!-- Q2 -->
    # etc.,
    $xml =~ s{(<!-- )<a href="http://www\.wormbase\.org\S+?" id=".+?">(.+?)</a><a href=".+?"><sup><img src="\S+?"/></sup></a>( -->)}
             {$1$2$3}g;

    my @xmls = split(/\n/, $xml);
    my $ret = "";

    for $xml (@xmls) {
        if ($xml =~ /^<contrib contrib-type="author"/) {
            # then leave the links; these are author links
        } 
        elsif (dontLinkLine($xml, NLM_XML_ID)) {
            $xml =~ s{<a href="http://www\.wormbase\.org/.+?" id=".+?">(.+?)</a><a href=".+?"><sup><img src="\S+?"/></sup></a>}{$1}g;
            $xml =~ s{<a href="http://www\.wormbase\.org/.+?">(.+?)</a>}{$1}g; # for GSP-3/4 - link to 4
        } 

        # if gene followed by :: remove link
        $xml =~ s{<a href="http://www\.wormbase\.org/db/get\?name=\S+?;class=Gene" id=".+?">(\S+?)</a><a href=".+?"><sup><img src="\S+?"/></sup></a>(</I>)?(::)}{$1$2$3}g;

        # if gene preceded by : remove link
        $xml =~ s{(:)<a href="http://www\.wormbase\.org/db/get\?name=\S+?;class=Gene" id=".+?">(\S+?)</a><a href=".+?"><sup><img src="\S+?"/></sup></a>}{$1$2$3}g;
                
        # Unlink genes that have a suffix 'p'
        # <a href="http://www.wormbase.org/db/get?name=aex-3;class=Gene">aex-3</a><SUB>p</SUB>
        # $xml =~ s/\<a href=\"http\:\/\/www\.wormbase\.org\/db\/get\?name=\S+?\;class=Gene\"\>(\S+?)\<\/a\>(\<SUB\>p\<\/SUB\>)/$1$2/g;
        $xml =~ s{<a href="http://www\.wormbase\.org/db/get\?name=\S+?;class=Gene" id=".+?">(\S+?)</a><a href=".+?"><sup><img src="\S+?"/></sup></a>(<SUB>p</SUB>)}{$1$2}g;

        # Phenotype entity linking part to not link terms with in italics.
        $xml =~ s#(<I>)<a href="http://www\.wormbase\.org/db/get\?name=\S+?\;class=Phenotype" id=".+?">(\S+?)</a><a href=".+?"><sup><img src="\S+?"/></sup></a>(</I>)#$1$2$3#g;

        $ret .= $xml."\n";
    }
    return $ret;
}

sub removeUnwantedLinksFlatXml {
    my $xml = shift;

    my @xmls = split(/\n/, $xml);
    my $ret = "";

    for my $line (@xmls) {
        if (dontLinkLine($line, FLAT_XML_ID)) {
            $line =~ s#<a href="http://www\.wormbase\.org/.+?">(.+?)</a>#$1#g;
        } 
        elsif ($line !~ m#<Authors>.+</Authors>#) { # remove persons other than authors (in Authors tag) getting linked
            $line =~ s#<a href="http://www\.wormbase\.org/db/misc/person\?name=.+?">(.+?)</a>#$1#g;
        }

        # do not link only the gene part in transgenes. eg: do not link eor-1p or EOR-1 in eor-1p::EOR-1::GFP
        #$line =~ s/\<a href=\"http\:\/\/www\.wormbase\.org\/db\/gene\/gene\?name=\S+?\;class=Gene\"\>(\S+?)\<\/a\>(\:)/$1$2/g;
        $line =~ s/\<a href=\"http\:\/\/www\.wormbase\.org\/db\/get\?name=\S+?\;class=Gene\"\>(\S+?)\<\/a\>(\<\/I\>)?(\:\:)/$1$2$3/g;

        #$line =~ s/(\:)\<a href=\"http\:\/\/www\.wormbase\.org\/db\/gene\/gene\?name=\S+?\;class=Gene\"\>(\S+?)\<\/a\>/$1$2/g;
        $line =~ s/(\:)\<a href=\"http\:\/\/www\.wormbase\.org\/db\/get\?name=\S+?\;class=Gene\"\>(\S+?)\<\/a\>/$1$2/g;
        # <i><a href="http://www.wormbase.org/db/gene/gene?name=eor-1;class=Gene">eor-1p</a>::<a href="http://www.wormbase.org/db/gene/gene?name=EOR-1;class=Gene">EOR-1</a>::GFP</i>
                
        # Unlink genes that have a suffix 'p'
        # <a href="http://www.wormbase.org/db/get?name=aex-3;class=Gene">aex-3</a><SUB>p</SUB>
        $line =~ s/\<a href=\"http\:\/\/www\.wormbase\.org\/db\/get\?name=\S+?\;class=Gene\"\>(\S+?)\<\/a\>(\<SUB\>p\<\/SUB\>)/$1$2/g;

        # Please fix the
        # Phenotype entity linking part to not link terms with in italics.
        # Phenotype terms should only be automatically linked if they occur
        # like "Hin" -first letter capitalized and plain text only.
        $line =~ s#(<I>)<a href="http://www\.wormbase\.org/db/get\?name=\S+?\;class=Phenotype">(\S+?)</a>(</I>)#$1$2$3#g;

        $ret .= $line."\n";
    }
    return $ret;
}

sub removeXmlStuff {
    my $line = shift;
    $line =~ s/\<.+?\>/ /g;
    $line =~ s/\&#x(\S+?);//g;
    return $line;
}

sub loadLexicon {
    my $lexicon_ref = shift;
    my $sorted_entries_ref = shift;

    my %classes = ();
    open (IN, "<lexicon") or die ("Died: no lexicon input file named lexicon found in this dir\n");
    print "Loading lexicon...\n";
    while (my $lexicon_line = <IN>) {
        chomp($lexicon_line);
        my $entity_name;
        my $entity_id;
        my $class_name;
        my @entries = split(/\t/, $lexicon_line);

        if (scalar(@entries) == 3) { # like "entity_name    entity_id   class_name"
            ($entity_name, $entity_id, $class_name) = @entries;
        } 
        else { # like "entity_name  class_name" - entity_name itself is also entity_id
            ($entity_name, $class_name) = @entries;
            $entity_id = $entity_name;
        }
        $lexicon_ref->{$entity_name}{$class_name} = $entity_id;
        push @$sorted_entries_ref, $entity_name;
    }
    close (IN);

    print "done.\n";
    print "Size of lexicon = " . scalar(keys %$lexicon_ref) . "\n\n";
}

sub writeOutput {
    my $infile = shift;
    my $outdir = shift;
    my $linked_xml = shift;

    # save the linked file on server
    my $outfile = $outdir . "/" . getFileName($infile) . "_linked.xml";
    open (OUT,">$outfile") or die ("Died. could not open $outfile for writing.");
    print OUT "$linked_xml\n";
    close (OUT);

    # ftp the linked file to dartmouth
    use Net::FTP;
    print "FTPing outfile to dartmouth\n";
    my $ftp = Net::FTP->new("ftp1.dartmouthjournals.com", Passive=>1) or die ("Died: Could connect to dartmouth ftp server");
    $ftp->login('genetics', '22dna25') or die ("could not authenticate");
    $ftp->cwd("WormBase") or die ("could not change working dir to WormBase\n");
    my $fn = getFileName($infile)."_linked.xml";
    $ftp->put($outfile, $fn) or die ("Could not put file using FTP: $@\n");

    # change the file extension to HTML for easy viewing of links
    my $html_file = $outdir . "/" . getFileName($infile) . ".html";
    my @args = ("mv", $outfile, $html_file);
    system(@args) == 0 or die ("Died: could not move file in $outdir\n");

    # email people
}

sub getFileName {
    my $infile = shift;
    my @e = split(/\//, $infile);
    my $ret = pop @e;
    $ret =~ s/\.\S+$//;
    return($ret);
}

sub regexForXml {
    my $entry = shift;
    my @letters = split(//, $entry);
    my $regex = join ("\<?.+?\>?", @letters); # ct46gf is in XML removed stuff. ct46</I>gf is in XML
    return ($regex);
}

sub getStopWords {
    my $f = shift;
    open (IN, "<$f") or die ("could not open $f for reading!\n");
    my $s = '(';
    while (<IN>) {
        chomp;
        $s .= $_ . '|';
    }
    $s =~ s/\|$//;
    $s .= ')';
    return $s;
}

sub getPhenotypeIds {
    my $file = shift;
    open (IN, "<$file") or die ("died: no infile $file\n");
    my %hash = ();
    while (my $line = <IN>) {
        chomp($line);
        (my $name, my $id) = split(/\t/, $line);
        $hash{$name} = $id;
    }
    close IN;
    return %hash;
}

sub getPersonIds {
    my $file = shift;
    open (IN, "<$file") or die ("died: no infile $file\n");
    my %hash = ();
    while (my $line = <IN>) {
        chomp($line);
        (my $name, my $id) = split(/\t/, $line);
        $hash{$name} = $id;
    }
    close IN;
    return %hash;
}

# the sub-routine below is not used now, but will be useful if pattern matching should
# be used for entity recognition

sub formEntityTable {
    my $linked_xml = shift;
    my $xml_format = shift;
    my $wbpaper_id = shift;
    my $outfile = shift;
    my $log_file = shift;
    my $pipeline_stage = shift; # "first pass" or "post QC"

    #undef($/); open (IN, "<$linked_xml_file") or die $!;
    #my $linked_xml = <IN>; close (IN); $/ = "\n";

    # get different docId's for the article
    my $doi = GeneralTasks::getDoi($linked_xml, $xml_format);
    my $genetics_id = GeneralTasks::getGeneticsId($linked_xml, $xml_format);

    open (OUT, ">$outfile") or die ("Could not open $outfile for writing: $!");
    print OUT "<HTML>\n";
    print OUT "<HEAD>\n";

    if ($pipeline_stage eq "first pass") {
        print OUT "<TITLE>First pass entity table for $wbpaper_id</TITLE>\n";
        print OUT "</HEAD>\n";
        print OUT "<BODY BGCOLOR=\"Silver\">\n";
        print OUT "<H1><font color=\"red\">This is the first pass entity table.</font></H1>\n";
    } else {
        print OUT "<TITLE>Entity table for $wbpaper_id</TITLE>\n";
        print OUT "</HEAD>\n";
        print OUT "<BODY BGCOLOR=\"#AABBCC\">\n";
    }

    print OUT "<H2> Genetics DOI: $doi</H2>\n";
    print OUT "<H2> WB Paper ID : $wbpaper_id</H2>\n";
    #print OUT "<H2> Genetics ID : $genetics_id</H2>\n";

    print OUT "<H3> Title : ",   GeneralTasks::getArticleTitle($linked_xml, $xml_format), " </H3>\n";
    print OUT "<H3> Authors : ", GeneralTasks::getAuthors($linked_xml, $xml_format),      " </H3>\n";

    print OUT "<p> <B>Note </B>:<br/>" . 
              "The links that are flagged 'live' have a current and valid WormBase page. <br/>" . 
              "The links that are flagged as <font color=\"red\">silent</font> are new entities and are not currently live, ".
              "but have been forwarded to an appropriate WormBase curator. They will become live soon. <br/>" .
              "The links that are flagged as <font color=\"magenta\">read timeout</font> are the ones for which ".
              "WormBase did not return anything within 60 secs at the time the script checked the link. " .
              "Most likely these links are live, so please click on the link manually and verify. <br/>" .
              "If you have any questions or find any errors please contact Karen Yook at kyook\@caltech.edu </p>";
    
    print OUT "<TABLE BORDER=1>\n";
    print OUT "<TR> <TD><B>Entity class</B></TD> <TD><B>Entity name</B></TD> <TD><B>link</B></TD> <TD><B>link status</B></TD> ".
              " <TD><B>Relevant content from URL</B></TD> <TD><B># of linked occurrences</B></TD> </TR>\n";

    my %entity_url_hash = ();
    my $total_num_links = 0;
    while ($linked_xml =~ m{<a href="(http://www\.wormbase\.org/.+?)"( id=".+?")?>(.+?)</a>}g) {
        my $url = $1;
        my $entity_name = $3;

        if (not defined($entity_url_hash{$entity_name}{$url})) {
            $entity_url_hash{$entity_name}{$url} = 1;
        } else {
            $entity_url_hash{$entity_name}{$url}++;
        }
        $total_num_links++;
    }

    # append to log file just to check if the script is run multiple times for any genetics paper
    open(LOG, ">>$log_file") or die("could not open log file $log_file for writing: $!\n"); 
    # print start time to log file
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    printf LOG "Begin time = %4d-%02d-%02d %02d:%02d:%02d\n\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;

    my %hash = ();
    for my $entity (sort keys %entity_url_hash) {
        for my $link (sort {lc($a) cmp lc($b)} keys %{$entity_url_hash{$entity}}) {
            my $class = getEntityClass($link);
            #my $link_status = isLivePage( $link );
    
            # log
            print LOG "$entity\t$class\t$link\n";
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
            printf LOG "%4d-%02d-%02d %02d:%02d:%02d\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;
            my $contents = get_web_page($link); # link is to wormbase, so use get_web_page
            #print "$contents\n";

            if ( ($contents =~ /has no record for/i) || # For missing Person, WormBase page says "has no record for Lisa L. Maduzia".
                 ($contents =~ /No results found/i)  || # missing objects for other classes 
                 ($contents =~ /not found in the database/i)  
               ) { 
                $hash{$class}{$entity}{"silent"} = $link;
                print "Entity: $entity\tClass: $class\tStatus: silent\n\n";
                print LOG "Status: silent\n";
            } 
            elsif ( $contents =~ /500 read timeout/i) {  
            # trouble with wormbase; either wormbase is down or wormbase not allowing requests from textpresso-dev
                $hash{$class}{$entity}{"read timeout"} = $link;
                print "Entity: $entity\tClass: $class\tStatus:timeout\n";
                print LOG "Status: 500 read timeout\n";
            } 
            else { # live
                # extract some content from the downloaded page for display on the entity table

                # put the entire content in one line for easy pattern matching below
                my @lines = split(/\n/, $contents);
                $contents = join(" ", @lines);

                # get the title
                $contents =~ /<title>(.+?)<\/title>/i;
                my $title = $1;
                $title =~ s/\(WB.+?\)//g; # removes the unwanted WBid stuff
                $title =~ s/\s{2,}/ /g;

                # extract contents from some fields. rest simply display title only.
                if ($class eq "Variation") {
                    $contents =~ /<th.+?>\s*Corresponding\s+gene:.+?<a.+?>(.+?)<\/a>/i;
                    my $gene = $1;

                    # remove the unwanted WBgeneID
                    $gene =~ s/\(WBGene.+?\)//g;
                    $gene =~ s/\s+$//;

                    $hash{$class}{$entity}{"<B>Title</B>: '$title' <BR/> <B>Corresponding gene</B>: '$gene'"} = $link;
                } 
                elsif ($class eq "Phenotype") {
                    $contents =~ /<th.+?>\s*Primary\s+name:.+?<a.+?>(.+?)<\/a>/i;
                    my $primary_name = $1;

                    $hash{$class}{$entity}{"<B>Title</B>: '$title' <BR/> <B>Primary name</B>: '$primary_name'"} = $link;
                } 
                elsif ($class eq "GO") {
                    $contents =~ m#<th.+?>\s*Term:.*?<td.*?>(.+?)</td>#i;
                    my $GO_term = $1;
                    print "GO_term = $GO_term\n";

                    if ($title eq 'Gene Ontology Search') {
                        $hash{$class}{$entity}{"<font color=\"grey\"><B>Title</B>: '$title' <BR/> <B>Term</B>: '$GO_term'<\/font>"} = $link;
                    }
                    else {
                        $hash{$class}{$entity}{"<B>Title</B>: '$title' <BR/> <B>Term</B>: '$GO_term'"} = $link;
                    }
                } 
                else {
                    $hash{$class}{$entity}{"<B>Title</B>: '$title'"} = $link;
                }

                print "Entity: $entity\tClass: $class\tStatus: live\n\n";
                print LOG "Status: live\n";
            }
            
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
            printf LOG "%4d-%02d-%02d %02d:%02d:%02d\n\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;
        }
    }
    # print end time to log file
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    printf LOG "End time: %4d-%02d-%02d %02d:%02d:%02d\n\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;
    close(LOG);

    for my $class (sort keys %hash) {
        for my $entity (sort {lc($a) cmp lc($b)} keys %{$hash{$class}}) {
            for my $status (keys %{$hash{$class}{$entity}}) {
                my $link = $hash{$class}{$entity}{$status};

                my $link_display = "<a href=\"$link\">$link</a>";

                my $class_display = $class;
                $class_display = "Gene/Protein" if ($class eq "Gene"); 

                my $num_occurrences = $entity_url_hash{$entity}{$link};
                
                if ($status eq "silent") {
                    print OUT "<TR> <TD>$class_display</TD> <TD><B>$entity</B></TD> <TD>$link_display</TD> ." .
                                "<TD><font color=\"red\">$status</font></TD> <TD>''</TD> <TD>$num_occurrences</TD> </TR>\n";
                } elsif ($status eq "read timeout") {
                    print OUT "<TR> <TD>$class_display</TD> <TD><B>$entity</B></TD> <TD>$link_display</TD> ." .
                                "<TD><font color=\"magenta\">$status</font></TD> <TD>''</TD> <TD>$num_occurrences</TD> </TR>\n";
                } else { # the status itself has some content downloaded from the URL
                    print OUT "<TR> <TD>$class_display</TD> <TD><B>$entity</B></TD> <TD>$link_display</TD> ." .
                            "<TD><font color=\"black\">live</font></TD> <TD>$status</TD> <TD>$num_occurrences</TD> </TR>\n";
                }
            }
        }
    }
    print OUT "<TR> <TD></TD> <TD></TD> <TD></TD> <TD></TD> <TD><B>TOTAL</B></TD> <TD><B>$total_num_links</B></TD> </TR>\n";
    print OUT "</TABLE>\n";
    print OUT "</BODY>\n";
    print OUT "</HTML>\n";
    close OUT;
}

sub getEntityClass {
    my $link = shift;

    if ( ($link =~ /(Gene)/) || ($link =~ /(Strain)/) || ($link =~ /(Clone)/) || ($link =~ /(Transgene)/) ||
         ($link =~ /(Rearrangement)/) || ($link =~ /(Sequence)/) || ($link =~ /(Phenotype)/) ) {
        return $1;
    } elsif ($link =~ /Variation/i) {
        return "Variation";
#    } elsif ($link =~ /anatomy/i) {
#        return "Anatomy";
    } elsif ($link =~ /person/i) {
        return "Person";
    } elsif ($link =~ /GO_term/i) {
        return "GO";
    }

    die "died: The link $link does not have a valid entity class\n";
}

sub getWbPaperId {
    my $filename = shift; # filename is like gen115485fin_WB.XML
    $filename =~ /(\d+)/;
    my $genetics_id = $1;
    
    my $web_page = "http://tazendra.caltech.edu/~postgres/cgi-bin/journal/journal_all.cgi";
    my $contents = TextpressoGeneralTasks::getwebpage($web_page);
    my @lines = split(/\n/, $contents);

    my $wbpaper_id;
    for (my $i=0; $i<@lines; $i++) {
        if ($lines[$i] =~ /\.$genetics_id<\/td>/) {
            # this line is like 
            # <td align="center">doi10.1534/genetics.111.128421</td>
            #
            # the next line is like 
            # <td align="center"><a href="http://tazendra.caltech.edu...">00032266</a></td>
            $lines[$i+1] =~ /\>(\d+)\</;
            $wbpaper_id = "WBPaper" . $1;
            last;
        }
    }

    return $wbpaper_id;
}

sub getAuthorObjects {
    my $contents = shift;
    my $af_page = "http://tazendra.caltech.edu/~postgres/cgi-bin/journal/journal_all.cgi?action=Show+Data&type=textpresso";
    
    # $contents = TextpressoGeneralTasks::InverseReplaceSpecChar($contents);
    $contents =~ /\<doi\>(.+)\<\/doi\>/; # <doi>10.1534/genetics.110.115188</doi>
    my $doi = "doi".$1;

    my $author_form_contents = TextpressoGeneralTasks::getwebpage($af_page);
    my @lines = split(/\n/, $author_form_contents);

    my $wbpaper_id = 0;
    my %data_entries = ();
    
    for (my $i = 0; $i < @lines; $i++) {
        if ($lines[$i] eq "<tr>") {
            my $doi_in_form = $lines[$i+1];
            $doi_in_form =~ s/\<.+?\>//g;
            if ($doi_in_form eq $doi) {
                $wbpaper_id = $lines[$i+2];
                $wbpaper_id =~ s/\<.+?\>//g;

                my $data_line = $lines[$i+4];
                $data_line =~ s/\<.+?\>//g;

                # remove invalid data i.e. anything after ~~
                $data_line =~ s/~~.+$//;
                # remove stuff inside [ ]
                $data_line =~ s/\[.+?\]//g;
                # assuming author data is comma-separated
                my @entries = split(/\,/, $data_line);

                for my $e (@entries) {
                    $e =~ s/^\s+//;
                    $data_entries{$e} = 1;
                }
            }
        }
    }
    
    return %data_entries;
}

# this sub-routine may need clean-up later if more curators are added
# or if the curator name changes!
sub getResponsibleCurator {
    # for GO evaluation only
    # return "everyone";
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
            = localtime(time); # $mon = 0 for Jan

    my @curator_emails = @{(WormbaseLinkGlobals::CURATOR_EMAILS)};

    # round robin on 3 curators depending on month
    my $responsible_curator_email = $curator_emails[ $mon % 3 ];
    my ($user_name, $domain_name) = split(/\@/, $responsible_curator_email);

    if ($user_name eq "karen") {
        $user_name = "Karen Yook";
    } elsif ($user_name eq "cgrove") {
        $user_name = "Christian A. Grove";
    } elsif ($user_name eq "draciti") {
        $user_name = "Daniela Raciti";
    }

    return $user_name;
}

sub replaceAnchorTagsInLinkedXml {
    my $linkedxmlfile = shift;

    my $output = "";
    open(IN, "<$linkedxmlfile") or die("died: could not open $linkedxmlfile for reading\n");
    while (my $line = <IN>) {
        if ($line =~ /^<contrib contrib-type="author"/) { # author name links
            $line =~ s/<name><surname><a href="(http:\/\/www\.wormbase\.org.+?)">(.+?)<\/a><\/surname><given-names><a href="http:\/\/www\.wormbase\.org\/.+?">(.+?)<\/a><\/given-names><\/name>/<name><surname>$2<\/surname><given-names>$3<\/given-names><\/name><ext-link ext-link-type="uri" xlink:href="$1"\/>/g;
        }
        else {
            $line =~ s/<a href="(http:\/\/www\.wormbase\.org\/.+?)">(.+?)<\/a>/<ext-link ext-link-type="uri" xlink:href="$1">$2<\/ext-link>/g;
        }
        
        $output .= $line;
    }
    close(IN);

    # output to same file
    open(OUT, ">$linkedxmlfile") or die("died: could not open $linkedxmlfile for writing.\n");
    print OUT $output;
    close(OUT);

    return;
}

sub isLivePage {
    my $link = shift;
    
    my $contents = get_web_page($link);
    print "$contents\n";

    if ( ($contents =~ /has no record for/i) || # For missing Person, WormBase page says "has no record for Lisa L. Maduzia".
         ($contents =~ /No results found/i)  || # missing objects for other classes 
         ($contents =~ /not found in the database/i)  ) { 
        return 0;
    } elsif ( $contents =~ /500 read timeout/i) {
        return -1;
    } else {
        return 1;
    }
}

sub getSender {
    return WormbaseLinkGlobals::DEVELOPER_EMAIL;
}

sub getReceivers {
    my @receivers = ();
    for my $rec ( @{(WormbaseLinkGlobals::CURATOR_EMAILS)} ) {
        push @receivers, $rec;
    }
    
    # keep the sender informed about the emails
    push @receivers, getSender();

    return @receivers;
}

sub get_entity_class {
    # if there are two entity classes and one of them is 'GO'
    # return the other class
    my @classes = @_;
    
    if (@classes > 1) { # multiple classes have this term
        for my $class (@classes) {
            return $class if ($class ne "GO");
        }
    } 
    else {
        return $classes[0];
    }
}

sub get_matched_entity_id {
    # id is required bcos multiple terms map to same GO id.
    my $url = shift;
    my $entity_of_ref = shift;
    my $entity_name = shift;
    
    my $id = 0;
    if (! defined $entity_of_ref->{$url}) {
        $id = 1;
    }
    else {
        my @ids = keys %{ $entity_of_ref->{$url} };
        $id = scalar(@ids) + 1;
    }
    
    $entity_of_ref->{$url}{$id} = $entity_name;
    print "entity = '$entity_name', url = '$url', id = '$id'\n";

    return $id;
}

sub original_txt_is_preserved {
    my $original = shift;
    my $linked   = shift;
    my $gsa_id   = shift;

    # delete all links to entities
    $linked =~ s{<a href="\S+?" id=".+?">(.+?)</a><a href=".+?"><sup><img \S+?/></sup></a>}
                {$1}g;

    # special case for WB - delete author links
    $linked =~ s{<a href="http://www\.wormbase\.org/\S+?">(.+?)</a>}
                {$1}g;

    my @orig_lines   = split /\n/, $original;
    my @linked_lines = split /\n/, $linked;

    for (my $i=0; $i<@orig_lines; $i++) {
        if ($orig_lines[$i] ne $linked_lines[$i]) {
            print   "FATAL ERROR in linking. Text changed.\n\n" 
                  . "Incoming line:\n$orig_lines[$i]\n\n" 
                  . "Linked line:\n$linked_lines[$i]\n";

            # email the developer with the error
            mailer( WormbaseLinkGlobals::DEVELOPER_EMAIL,
                    WormbaseLinkGlobals::DEVELOPER_EMAIL,
                    "Fatal error in WB GSA file $gsa_id (Text changed during linking)",
                    "Original line:\n$orig_lines[$i]\n\n"
                    . "Linked line:\n$linked_lines[$i]\n" 
                  );

            return 0;
        }
    }

    return 1;
}


1;
