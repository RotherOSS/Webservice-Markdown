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

use strict;
use warnings;
use utf8;

# core modules

# CPAN modules
use Test2::V0;

# OTOBO modules
use Kernel::System::UnitTest::RegisterOM;    # Set up $Kernel::OM

my $MarkdownObject = $Kernel::OM->Get('Kernel::System::Markdown');

skip_all('Markdown::Perl is not installed') unless $MarkdownObject->IsAvailable( Direction => 'ToHTML' );

# ToHTML() without the needed parameter String
{
    my $HTML = $MarkdownObject->ToHTML();
    is( $HTML, undef, 'ToHTML() without String returns undef' );
}

# Each test checks for the presence of some substrings in the generated HTML
# and for the absence of others. The exact HTML is not compared, as the output
# of Markdown::Perl might change slightly between versions.
my @Tests = (
    {
        Name     => 'empty string',
        Markdown => '',
        Contains => [],
        Lacks    => ['<'],
    },
    {
        Name     => 'paragraph with inline formatting',
        Markdown => 'Some *emphasis* and **strong** text with `code`.',
        Contains => [
            '<p>',
            '<em>emphasis</em>',
            '<strong>strong</strong>',
            '<code>code</code>',
        ],
    },
    {
        Name     => 'heading and link',
        Markdown => "# Heading\n\nA [link](https://otobo.io/).",
        Contains => [
            '<h1>Heading</h1>',
            '<a href="https://otobo.io/">link</a>',
        ],
    },
    {
        Name     => 'nested list',
        Markdown => "- item 1\n- item 2\n  - nested",
        Contains => [
            '<ul>',
            '<li>item 1</li>',
            '<li>nested</li>',
        ],
    },
    {
        Name     => 'GitHub table',
        Markdown => "| Col A | Col B |\n|-------|-------|\n| 1     | 2     |",
        Contains => [
            '<table>',
            '<th>Col A</th>',
            '<td>2</td>',
        ],
    },
    {
        Name     => 'GitHub task list',
        Markdown => "- [ ] open\n- [x] done",
        Contains => [
            'type="checkbox"',
            'checked=""',
        ],
    },
    {
        Name     => 'fenced code block',
        Markdown => "```perl\nmy \$x = 1;\n```",
        Contains => [
            '<pre><code class="language-perl">my $x = 1;',
        ],
    },
    {
        Name     => 'GitHub autolink and strikethrough',
        Markdown => 'See https://github.com/RotherOSS/otobo/issues/1 and ~~old~~.',
        Contains => [
            '<a href="https://github.com/RotherOSS/otobo/issues/1">https://github.com/RotherOSS/otobo/issues/1</a>',
            '<del>old</del>',
        ],
    },
    {
        Name     => 'umlauts are kept',
        Markdown => 'Grüße aus München',
        Contains => ['Grüße aus München'],
    },
    {
        Name     => 'script tag is neutralized',
        Markdown => "Text\n\n<script>alert(1)</script>\n\nMore text",
        Contains => [ '<p>Text</p>', '<p>More text</p>', '&lt;script' ],
        Lacks    => ['<script'],
    },
    {
        Name     => 'javascript link is removed',
        Markdown => '<a href="javascript:alert(1)">click</a>',
        Contains => ['click'],
        Lacks    => ['javascript:'],
    },
    {
        Name     => 'onclick handler is removed',
        Markdown => '<span onclick="alert(1)">click</span>',
        Contains => ['click'],
        Lacks    => ['onclick'],
    },
    {
        Name     => 'image is kept',
        Markdown => '![alt text](https://otobo.io/image.png)',
        Contains => ['<img src="https://otobo.io/image.png" alt="alt text"'],
    },
    {
        Name     => 'cmark mode has no GitHub extensions',
        Markdown => 'Text with ~~strike~~.',
        Mode     => 'cmark',
        Contains => ['~~strike~~'],
        Lacks    => ['<del>'],
    },
);

for my $Test (@Tests) {
    subtest $Test->{Name} => sub {

        my $HTML = $MarkdownObject->ToHTML(
            String => $Test->{Markdown},
            ( $Test->{Mode} ? ( Mode => $Test->{Mode} ) : () ),
        );

        ok( defined $HTML, 'ToHTML() returned a defined value' );

        for my $Substring ( @{ $Test->{Contains} // [] } ) {
            ok( index( $HTML, $Substring ) > -1, "HTML contains '$Substring'" );
        }

        for my $Substring ( @{ $Test->{Lacks} // [] } ) {
            ok( index( $HTML, $Substring ) == -1, "HTML does not contain '$Substring'" );
        }
    };
}

done_testing;
