<?

require_once('session.php');

$skin_info = $freeside->skin_info( array(
  'session_id' => $_COOKIE['session_id'],
) );

extract($skin_info);

?>
<style type="text/css">
#menu_ul ul li {
  display: inline;
  width: 100%;
} 
</style>

<ul id="menu_ul">

<?

  $menu_array = array(
    'payment.php Payments', 
    'payment_cc.php Credit Card Payment',
    'payment_ach.php Electronic check payment',
    'payment_paypal.php PayPal payment',
    'payment_webpay.php Webpay payment',
  );
  $submenu = array(); 

  foreach ($menu_array AS $menu_item) {
    if ( preg_match('/^\s*$/', $menu_item) ) {
      print_menu($submenu, $current_menu, $menu_disable);
      $submenu = array();
    } else {
      $submenu[] = $menu_item;
    }
  }
  print_menu($submenu, $current_menu, $menu_disable);

  function print_menu($submenu_array, $current_menu, $menu_disable) {
    if ( count($submenu_array) == 0 ) { return; }

    $links = array();
    $labels = array();
    foreach ($submenu_array AS $submenu_item) {
      $pieces = preg_split('/\s+/', $submenu_item, 2, PREG_SPLIT_NO_EMPTY);
      $links[] = $pieces[0];
      $labels[] = $pieces[1];
    }

    print_link($links[0], $labels[0], $current_menu, $links);

    if ( count($links) > 1 ) {
      if ( in_array( $current_menu, $links ) ) {
        echo '<img src="images/dropdown_arrow_white.gif">';
      } else {
        echo '<img src="images/dropdown_arrow_white.gif" style="display:none;">';
        echo '<img src="images/dropdown_arrow_grey.gif">';
      }
    }

    array_shift($links);
    array_shift($labels);

    echo '</a>';

    if ( count($links) > 0 ) {
      echo '<ul>';
      foreach ($links AS $link) {
        $label = array_shift($labels);
        if ( in_array($label, $menu_disable) == 0) {
          print_link($link, $label, $current_menu, array($link) );
          echo '</a></li>';
        }
      }
      echo '</ul>';
    }

    echo '</li>';

  }

  function print_link($link, $label, $current_menu, $search_array) {
      echo '<li><a href="'. $link. '"';
      if ( in_array( $current_menu, $search_array ) ) {
        echo ' class="current_menu"';
      }
      echo '>'. _($label);
  }

?>

</ul>

<div style="clear:both;"></div>
<table cellpadding="0" cellspacing="0" border="0" style="min-width:666px">
<tr>
<td class="page">