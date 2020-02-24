do ($) ->

    blocks = {

        initialize: () ->
            $xs = $ 'pre'
            for x in $xs
                $x = $ x
                $y = $x.find 'code'
                if $y.width() > $x.width()
                    $x.on 'mouseenter', @expand
                    $x.on 'mouseleave', @contract

        expand: (e) ->
            $x = $ e.currentTarget
            $y = $x.find 'code'
            $x.css 'width', $y.width()

        contract: (e) ->
            $x = $ e.currentTarget
            $x.css 'width': 'auto', 'overflow': 'hidden'
    }

    $ () ->
        blocks.initialize()
