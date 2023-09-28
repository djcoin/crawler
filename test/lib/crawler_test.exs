defmodule CrawlerTest do
  use Crawler.TestCase, async: false

  alias Crawler.Store

  doctest Crawler

  @moduletag capture_log: true

  test ".crawl", %{bypass: bypass, url: url} do
    url = "#{url}/crawler"
    linked_url1 = "#{url}/link1"
    linked_url2 = "#{url}/link2"
    linked_url3 = "#{url}/link3"
    linked_url4 = "#{url}/link4"

    Bypass.expect_once(bypass, "GET", "/crawler", fn conn ->
      Plug.Conn.resp(conn, 200, """
        <html><a href="#{linked_url1}">1</a></html>
        <html><a href="#{linked_url2}">2</a></html>
      """)
    end)

    Bypass.expect_once(bypass, "GET", "/crawler/link1", fn conn ->
      Plug.Conn.resp(conn, 200, """
        <html><a id="link2" href="#{linked_url2}" target="_blank">2</a></html>
      """)
    end)

    Bypass.expect_once(bypass, "GET", "/crawler/link2", fn conn ->
      Plug.Conn.resp(conn, 200, """
        <html><a href="#{linked_url3}">3</a></html>
      """)
    end)

    Bypass.expect_once(bypass, "GET", "/crawler/link3", fn conn ->
      Plug.Conn.resp(conn, 200, """
        <html><a href="#{linked_url4}">4</a></html>
      """)
    end)

    {:ok, opts} = Crawler.crawl(url, max_depths: 3, workers: 3, interval: 100)

    Crawler.pause(opts)

    assert opts[:workers] == 3
    assert OPQ.info(opts[:queue]) == {:paused, %OPQ.Queue{data: {[], []}}, 2}

    Crawler.resume(opts)

    assert OPQ.info(opts[:queue]) == {:normal, %OPQ.Queue{data: {[], []}}, 2}

    wait(fn ->
      page = Store.find_processed(url)

      assert page
      assert page.opts[:workers] == 3

      assert Store.find_processed(linked_url1)
      assert Store.find_processed(linked_url2)
      assert Store.find_processed(linked_url3)
      refute Store.find(linked_url4)

      urls = Crawler.Store.all_urls()

      assert Enum.member?(urls, url)
      assert Enum.member?(urls, linked_url1)
      assert Enum.member?(urls, linked_url2)
      assert Enum.member?(urls, linked_url3)
      refute Enum.member?(urls, linked_url4)
    end)

    wait(fn ->
      assert OPQ.info(opts[:queue]) == {:normal, %OPQ.Queue{data: {[], []}}, 3}
    end)
  end

  test ".crawl stopped", %{bypass: bypass, url: url} do
    url = "#{url}/stop"
    linked_url = "#{url}/stop1"

    Bypass.expect_once(bypass, "GET", "/stop", fn conn ->
      Plug.Conn.resp(conn, 200, """
        <html><a href="#{linked_url}">1</a></html>
      """)
    end)

    {:ok, opts} = Crawler.crawl(url, workers: 1, interval: 500)

    Process.sleep(200)

    Crawler.stop(opts)

    refute Store.find(linked_url)
  end
end
