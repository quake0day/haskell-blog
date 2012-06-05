<!DOCTYPE html>
<html lang="en">
  <apply template="head" />

  <body>
    <apply template="topnav" />

    <div class="container">
      <posts />
      <pagination />
	  <apply template="footer" />	
    </div> <!-- /container -->

    <apply template="foot" />
	<script type="text/javascript">
    var disqus_shortname = 'dikmax';

    /* * * DON'T EDIT BELOW THIS LINE * * */
    (function () {
        var s = document.createElement('script'); s.async = true;
        s.type = 'text/javascript';
        s.src = 'http://' + disqus_shortname + '.disqus.com/count.js';
        (document.getElementsByTagName('HEAD')[0] || document.getElementsByTagName('BODY')[0]).appendChild(s);
    }());
</script>
  </body>
</html>
