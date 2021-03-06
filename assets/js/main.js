// Generated by CoffeeScript 2.5.1
(function() {
  (function($) {
    var blocks;
    blocks = {
      initialize: function() {
        var $x, $xs, $y, i, len, results, x;
        $xs = $('pre');
        results = [];
        for (i = 0, len = $xs.length; i < len; i++) {
          x = $xs[i];
          $x = $(x);
          $y = $x.find('code');
          if ($y.width() > $x.width()) {
            $x.on('mouseenter', this.expand);
            results.push($x.on('mouseleave', this.contract));
          } else {
            results.push(void 0);
          }
        }
        return results;
      },
      expand: function(e) {
        var $x, $y;
        $x = $(e.currentTarget);
        $y = $x.find('code');
        return $x.css('width', $y.width());
      },
      contract: function(e) {
        var $x;
        $x = $(e.currentTarget);
        return $x.css({
          'width': 'auto',
          'overflow': 'hidden'
        });
      }
    };
    return $(function() {
      return blocks.initialize();
    });
  })($);

}).call(this);
