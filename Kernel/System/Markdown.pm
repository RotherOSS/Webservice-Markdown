# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::System::Markdown;

use v5.24;
use strict;
use warnings;
use namespace::autoclean;
use utf8;

# core modules

# CPAN modules

# OTOBO modules

our @ObjectDependencies = (
    'Kernel::System::HTMLUtils',
    'Kernel::System::Log',
    'Kernel::System::Main',
);

=head1 NAME

Kernel::System::Markdown - converting between Markdown and HTML

=head1 DESCRIPTION

A module for converting Markdown text into HTML and HTML into Markdown.

The conversion from Markdown to HTML is done by the CPAN module L<Markdown::Perl>.
The generated HTML is cleaned by L<Kernel::System::HTMLUtils/Safety()> before it is returned,
so that active content like JavaScript is never passed on to the caller.

The conversion from HTML to Markdown is implemented in this module. It parses the HTML
with the CPAN module L<HTML::TreeBuilder> and generates GitHub flavoured Markdown.

Both CPAN modules are declared as required modules of the package.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $MarkdownObject = $Kernel::OM->Get('Kernel::System::Markdown');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = bless {}, $Type;

    return $Self;
}

=head2 IsAvailable()

checks whether the needed CPAN modules are installed.

    my $Available = $MarkdownObject->IsAvailable(
        Direction => 'ToHTML',      # 'ToHTML' or 'FromHTML'
    );

returns 1 when the converter for the given direction is available, otherwise an empty string.

=cut

sub IsAvailable {
    my ( $Self, %Param ) = @_;

    my $Direction = $Param{Direction} || 'ToHTML';

    # Each direction depends on a different CPAN module.
    my %NeededModule = (
        ToHTML   => 'Markdown::Perl',
        FromHTML => 'HTML::TreeBuilder',
    );

    my $Module = $NeededModule{$Direction};

    if ( !$Module ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Unknown direction '$Direction'!",
        );

        return;
    }

    # The result of the check is cached in the object, as the availability does not change at runtime.
    if ( !defined $Self->{IsAvailable}->{$Module} ) {
        $Self->{IsAvailable}->{$Module} = $Kernel::OM->Get('Kernel::System::Main')->Require(
            $Module,
            Silent => 1,
        ) ? 1 : '';
    }

    return $Self->{IsAvailable}->{$Module};
}

=head2 ToHTML()

converts a Markdown string into an HTML fragment. By default the GitHub flavoured Markdown dialect is used,
which supports tables, task lists, strikethrough and autolinks in addition to CommonMark.

    my $HTML = $MarkdownObject->ToHTML(
        String => $MarkdownString,
        Mode   => 'github',             # optional, default 'github'; also 'cmark' or 'markdown' are supported
    );

The returned HTML is an HTML fragment, not a complete HTML document. It has already been cleaned
with L<Kernel::System::HTMLUtils/Safety()>, so that scripts, applets, objects and embedded SVG are removed.
Links and images are kept, as the frontend applies its own rules for loading remote content.

returns the HTML string, or undef when the conversion was not possible.

=cut

sub ToHTML {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{String} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need String!',
        );

        return;
    }

    if ( !$Self->IsAvailable( Direction => 'ToHTML' ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'The CPAN module Markdown::Perl is not installed.',
        );

        return;
    }

    my $Mode = $Param{Mode} || 'github';

    # The converter objects are cached per mode, as creating them is relatively expensive.
    if ( !$Self->{Converter}->{$Mode} ) {
        $Self->{Converter}->{$Mode} = Markdown::Perl->new( mode => $Mode );
    }

    my $HTML = $Self->{Converter}->{$Mode}->convert( $Param{String} );

    # Markdown may contain raw HTML. Remove active content so that the result is safe for display.
    my %Safe = $Kernel::OM->Get('Kernel::System::HTMLUtils')->Safety(
        String       => $HTML,
        NoApplet     => 1,
        NoObject     => 1,
        NoEmbed      => 1,
        NoSVG        => 1,
        NoJavaScript => 1,
    );

    return $Safe{String};
}

=head2 FromHTML()

converts an HTML string into GitHub flavoured Markdown. The HTML can be a complete document or a fragment,
as it is e.g. generated by the rich text editor.

    my $Markdown = $MarkdownObject->FromHTML(
        String => $HTMLString,
    );

The following HTML elements are converted: headings, paragraphs, line breaks, bold, italic, strikethrough,
inline code, preformatted code blocks (with the language taken from a C<language-*> class), links, images,
ordered and unordered lists (also nested), block quotes, horizontal rules and tables. Tables are converted
into pipe tables, which means that the content of a cell is reduced to a single line.
All other elements are replaced by their text content. Scripts and styles are dropped.

returns the Markdown string, or undef when the conversion was not possible.

=cut

sub FromHTML {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{String} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need String!',
        );

        return;
    }

    if ( !$Self->IsAvailable( Direction => 'FromHTML' ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'The CPAN module HTML::TreeBuilder is not installed.',
        );

        return;
    }

    my $Tree = HTML::TreeBuilder->new;
    $Tree->ignore_unknown(0);
    $Tree->no_space_compacting(1);
    $Tree->store_comments(0);
    $Tree->parse_content( $Param{String} );
    $Tree->elementify;

    # Only the body is relevant. The head contains nothing that should end up in the Markdown.
    my $Body = $Tree->look_down( _tag => 'body' ) || $Tree;

    my $Markdown = $Self->_ElementToMarkdown(
        Element => $Body,
        Context => {},
    );

    $Tree->delete;

    # Clean up: no trailing whitespace on lines, at most one empty line between blocks.
    $Markdown =~ s{[ \t]+$}{}mg;
    $Markdown =~ s{\n{3,}}{\n\n}g;
    $Markdown =~ s{\A\n+}{};
    $Markdown =~ s{\n*\z}{\n};

    return $Markdown;
}

=begin Internal:

=head2 _ElementToMarkdown()

converts an HTML::Element and its children into Markdown. This method calls itself recursively.

    my $Markdown = $MarkdownObject->_ElementToMarkdown(
        Element => $HTMLElement,
        Context => {
            ListDepth => 1,     # nesting depth of the current list, 0 if not in a list
            InTable   => 1,     # 1 if the element is part of a table cell
        },
    );

Block elements are returned with a leading and a trailing blank line, so that the Markdown of
consecutive blocks can simply be concatenated. The caller collapses multiple blank lines.

=cut

sub _ElementToMarkdown {
    my ( $Self, %Param ) = @_;

    my $Element = $Param{Element};
    my $Context = $Param{Context} // {};

    my $Tag = lc( $Element->tag // '' );

    # elements that have no visible content
    return '' if $Tag eq 'script' || $Tag eq 'style' || $Tag eq 'head' || $Tag eq 'title';

    # The content of pre is kept as is. The language is taken from a nested code element, as generated by CKEditor.
    if ( $Tag eq 'pre' ) {
        my $CodeElement = $Element->look_down( _tag => 'code' );
        my $Language    = '';
        if ($CodeElement) {
            my $Class = $CodeElement->attr('class') // '';
            if ( $Class =~ m{language-(\S+)} ) {
                $Language = $1;
            }
        }

        my $Code = $Element->as_text;
        $Code =~ s{\n*\z}{};

        return "\n\n```$Language\n$Code\n```\n\n";
    }

    # tables are converted into pipe tables, handled separately as rows and cells have a fixed structure
    if ( $Tag eq 'table' ) {
        return $Self->_TableToMarkdown( Element => $Element );
    }

    # Convert the children first. This is the text content for inline elements and the block content for block elements.
    my $Content = $Self->_ChildrenToMarkdown(
        Element => $Element,
        Context => $Context,
    );

    # In a table cell there can be no line breaks and no block elements, everything is reduced to inline content.
    # Line breaks and block elements are replaced by a space, so that words do not run into each other.
    if ( $Context->{InTable} ) {
        return ' ' if $Tag eq 'br' || $Tag eq 'hr';
        return " $Content " if $Tag eq 'p' || $Tag eq 'div' || $Tag eq 'li' || $Tag =~ m{\Ah[1-6]\z};

        return $Self->_InlineToMarkdown( Tag => $Tag, Element => $Element, Content => $Content );
    }

    # headings
    if ( $Tag =~ m{\Ah([1-6])\z} ) {
        my $Level = $1;
        my $Text  = $Self->_CollapseWhitespace($Content);

        return "\n\n" . ( '#' x $Level ) . " $Text\n\n";
    }

    # paragraphs and other block containers
    if ( $Tag eq 'p' || $Tag eq 'div' || $Tag eq 'section' || $Tag eq 'article' || $Tag eq 'figure' || $Tag eq 'body' || $Tag eq 'html' ) {

        # A div is often used instead of a paragraph, e.g. in HTML emails. Single line breaks are kept.
        return "\n\n" . $Self->_TrimBlock($Content) . "\n\n";
    }

    if ( $Tag eq 'br' ) {
        return "\n";
    }

    if ( $Tag eq 'hr' ) {
        return "\n\n---\n\n";
    }

    if ( $Tag eq 'blockquote' ) {
        my $Quoted = $Self->_TrimBlock($Content);
        $Quoted =~ s{^}{> }mg;

        return "\n\n$Quoted\n\n";
    }

    # lists: the items are rendered by _ListToMarkdown, as they need the list type and the nesting depth
    if ( $Tag eq 'ul' || $Tag eq 'ol' ) {
        return $Self->_ListToMarkdown(
            Element => $Element,
            Context => $Context,
        );
    }

    # a list item outside a list, should not happen, treat it as a paragraph
    if ( $Tag eq 'li' ) {
        return "\n\n" . $Self->_TrimBlock($Content) . "\n\n";
    }

    return $Self->_InlineToMarkdown( Tag => $Tag, Element => $Element, Content => $Content );
}

=head2 _InlineToMarkdown()

converts inline elements like bold, italic, links and images.

=cut

sub _InlineToMarkdown {
    my ( $Self, %Param ) = @_;

    my $Tag     = $Param{Tag};
    my $Element = $Param{Element};
    my $Content = $Param{Content};

    if ( $Tag eq 'strong' || $Tag eq 'b' ) {
        return $Self->_WrapInline( $Content, '**' );
    }

    if ( $Tag eq 'em' || $Tag eq 'i' ) {
        return $Self->_WrapInline( $Content, '*' );
    }

    if ( $Tag eq 'del' || $Tag eq 's' || $Tag eq 'strike' ) {
        return $Self->_WrapInline( $Content, '~~' );
    }

    if ( $Tag eq 'code' ) {

        # The content of code was not escaped, see _ChildrenToMarkdown. Use more backticks when the code contains one.
        my $Fence = $Content =~ m{`} ? '``' : '`';

        return "$Fence$Content$Fence";
    }

    if ( $Tag eq 'a' ) {
        my $Href = $Element->attr('href') // '';
        my $Text = $Self->_CollapseWhitespace($Content);

        return $Text if !$Href;

        # OTOBO links the URLs in the article body, so the text is often the URL itself
        return "<$Href>" if $Text eq $Href;

        return "[$Text]($Href)";
    }

    if ( $Tag eq 'img' ) {
        my $Src = $Element->attr('src') // '';
        my $Alt = $Element->attr('alt') // '';

        # Inline images are not supported by Markdown, so they are mentioned only by their alternative text.
        return $Alt if !$Src || $Src =~ m{\Adata:}i;

        return "![$Alt]($Src)";
    }

    # check boxes of task lists, as generated from GitHub flavoured Markdown
    if ( $Tag eq 'input' ) {
        my $Type = lc( $Element->attr('type') // '' );

        return '' if $Type ne 'checkbox';

        return defined $Element->attr('checked') ? '[x]' : '[ ]';
    }

    # all other inline elements like span, u, font, sub, sup, label are replaced by their content
    return $Content;
}

=head2 _ChildrenToMarkdown()

converts the children of an element and concatenates the results.

=cut

sub _ChildrenToMarkdown {
    my ( $Self, %Param ) = @_;

    my $Element = $Param{Element};
    my $Context = $Param{Context};

    my $Tag = lc( $Element->tag // '' );

    my $Markdown = '';

    CHILD:
    for my $Child ( $Element->content_list ) {

        # text nodes are plain strings
        if ( !ref $Child ) {
            my $Text = $Child;

            # Whitespace in HTML is not significant, collapse it like the browser does.
            $Text =~ s{\s+}{ }g;

            # Characters with a meaning in Markdown are escaped, except inside code.
            if ( $Tag ne 'code' ) {
                $Text = $Self->_EscapeMarkdown($Text);
            }

            $Markdown .= $Text;

            next CHILD;
        }

        $Markdown .= $Self->_ElementToMarkdown(
            Element => $Child,
            Context => $Context,
        );
    }

    return $Markdown;
}

=head2 _ListToMarkdown()

converts an ordered or unordered list, including nested lists.

=cut

sub _ListToMarkdown {
    my ( $Self, %Param ) = @_;

    my $Element = $Param{Element};
    my $Context = $Param{Context};

    my $Ordered   = lc( $Element->tag ) eq 'ol';
    my $ListDepth = $Context->{ListDepth} // 0;
    my $Counter   = 0;

    my $Markdown = '';

    ITEM:
    for my $Item ( $Element->content_list ) {

        # only list items are expected here, ignore whitespace between them
        next ITEM if !ref $Item;
        next ITEM if lc( $Item->tag ) ne 'li';

        $Counter++;

        my $Marker = $Ordered ? "$Counter." : '-';

        my $Content = $Self->_ChildrenToMarkdown(
            Element => $Item,
            Context => {
                %{$Context},
                ListDepth => $ListDepth + 1,
            },
        );

        $Content = $Self->_TrimBlock($Content);

        # Indent continuation lines, e.g. of nested lists, so that they belong to this item.
        my $Indent = ' ' x ( length($Marker) + 1 );
        $Content =~ s{\n}{\n$Indent}g;

        $Markdown .= "$Marker $Content\n";
    }

    # Nested lists stay directly below their parent item, top level lists are separate blocks.
    return $ListDepth ? "\n$Markdown" : "\n\n$Markdown\n\n";
}

=head2 _TableToMarkdown()

converts a table into a GitHub flavoured pipe table. The first row is used as header row,
as a pipe table always needs one.

=cut

sub _TableToMarkdown {
    my ( $Self, %Param ) = @_;

    my $Element = $Param{Element};

    my @Rows;
    for my $Row ( $Element->look_down( _tag => 'tr' ) ) {
        my @Cells;
        for my $Cell ( $Row->look_down( _tag => qr{\A(td|th)\z} ) ) {
            my $Content = $Self->_ChildrenToMarkdown(
                Element => $Cell,
                Context => { InTable => 1 },
            );

            $Content = $Self->_CollapseWhitespace($Content);

            # the pipe is the cell delimiter and must not occur in the content
            $Content =~ s{\|}{\\|}g;

            push @Cells, $Content;
        }

        push @Rows, \@Cells;
    }

    return '' if !@Rows;

    # all rows get the same number of columns
    my $NumColumns = 0;
    for my $Row (@Rows) {
        $NumColumns = scalar @{$Row} if scalar @{$Row} > $NumColumns;
    }

    my @Lines;
    my $RowIndex = 0;
    for my $Row (@Rows) {
        my @Cells = @{$Row};
        push @Cells, '' while scalar @Cells < $NumColumns;

        push @Lines, '| ' . join( ' | ', @Cells ) . ' |';

        # the separator line after the header row
        if ( $RowIndex == 0 ) {
            push @Lines, '|' . ( ' --- |' x $NumColumns );
        }

        $RowIndex++;
    }

    return "\n\n" . join( "\n", @Lines ) . "\n\n";
}

=head2 _WrapInline()

wraps inline content in a Markdown delimiter like C<**>. Whitespace at the edges is moved
outside the delimiters, as e.g. C<** bold **> is not recognised as bold.

=cut

sub _WrapInline {
    my ( $Self, $Content, $Delimiter ) = @_;

    my ($Leading)  = $Content =~ m{\A(\s*)};
    my ($Trailing) = $Content =~ m{(\s*)\z};
    $Content =~ s{\A\s+}{};
    $Content =~ s{\s+\z}{};

    return $Leading . $Trailing if $Content eq '';

    return "$Leading$Delimiter$Content$Delimiter$Trailing";
}

=head2 _EscapeMarkdown()

escapes characters in plain text that would otherwise be interpreted as Markdown.

=cut

sub _EscapeMarkdown {
    my ( $Self, $Text ) = @_;

    # The angle bracket is included, as raw HTML is not wanted in the generated Markdown.
    $Text =~ s{([\\`*_~\[\]<])}{\\$1}g;

    # characters that are only special at the start of a line
    $Text =~ s{^(\s*)([#>+-])(\s)}{$1\\$2$3}mg;

    # a number followed by a dot at the start of a line would start an ordered list
    $Text =~ s{^(\s*\d+)\.(\s)}{$1\\.$2}mg;

    return $Text;
}

=head2 _CollapseWhitespace()

reduces all whitespace, including line breaks, to single spaces and trims the string.

=cut

sub _CollapseWhitespace {
    my ( $Self, $Text ) = @_;

    $Text =~ s{\s+}{ }g;
    $Text =~ s{\A\s+}{};
    $Text =~ s{\s+\z}{};

    return $Text;
}

=head2 _TrimBlock()

removes leading and trailing blank lines and spaces of a block and collapses multiple blank lines.

=cut

sub _TrimBlock {
    my ( $Self, $Text ) = @_;

    $Text =~ s{[ \t]+$}{}mg;
    $Text =~ s{\n{3,}}{\n\n}g;
    $Text =~ s{\A\s+}{};
    $Text =~ s{\s+\z}{};

    return $Text;
}

=end Internal:

=cut

1;
