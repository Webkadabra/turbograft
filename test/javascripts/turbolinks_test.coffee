describe 'Turbolinks', ->
  sandbox = null
  pushStateStub = null
  replaceStateStub = null

  ROUTE_TEMPLATE_INDEX = 2

  TURBO_EVENTS = [
    'page:change',
    'page:update',
    'page:load',
    'page:before-change',
    'page:before-partial-replace',
    'page:after-change',
    'page:after-node-removed',
    'page:fetch',
    'page:receive',
    'page:after-script-inserted',
    'page:after-link-inserted',
    'page:after-link-removed',
    'page:script-error'
  ]

  hasScript = (filename) ->
    document.querySelectorAll("script[src=\"#{ASSET_FIXTURES[filename]}\"]").length > 0

  assetFixturePath = (filename) ->
    path = ASSET_FIXTURES[filename]
    throw new Error("NO ASSET PATH FOR #{filename}") unless path?
    path

  assertScripts = (expected) ->
    assert.deepEqual(
      actual = scriptsInHead(),
      expectedAssets = expected.map(assetFixturePath),
      "expected scripts in head: #{actual} to match expected: #{expectedAssets}"
    )

  assertLinks = (expected) ->
    assert.deepEqual(
      actual = linksInHead(),
      expectedAssets = expected.map(assetFixturePath),
      "expected links in head: #{actual} to match expected: #{expectedAssets}"
    )

  scriptsInHead = ->
    [].slice.call(document.head.children)
      .filter((node) -> node.nodeName == 'SCRIPT')
      .map((node) -> node.getAttribute('src'))

  linksInHead = ->
    [].slice.call(document.head.children)
      .filter((node) -> node.nodeName == 'LINK')
      .map((node) -> node.getAttribute('href'))

  resetPage = ->
    document.head.innerHTML = ""
    document.body.innerHTML = """
      <div id="turbo-area" refresh="turbo-area"></div>
    """

  urlFor = (slug) ->
    window.location.origin + slug

  visit = ({options, url}, callback) ->
    $(document).one('page:load', (event) ->
      setTimeout((-> callback(event) if callback), 0)
    )
    Turbolinks.visit('/' + url, options)

  beforeEach ->
    sandbox = sinon.sandbox.create()
    pushStateStub = sandbox.stub(Turbolinks, 'pushState')
    replaceStateStub = sandbox.stub(Turbolinks, 'replaceState')
    sandbox.stub(Turbolinks, 'fullPageNavigate', -> $(document).trigger('page:load'))
    sandbox.useFakeServer()

    Object.keys(ROUTES).forEach (url) ->
      sandbox.server.respondWith('/' + url, ROUTES[url])
    sandbox.server.autoRespond = true

    $("script").attr("data-turbolinks-eval", false)
    $("#mocha").attr("refresh-never", true)

    resetPage()

  afterEach ->
    sandbox.restore()
    $(document).off(TURBO_EVENTS.join(' '))
    $("#turbo-area").remove()

  it 'is defined', ->
    assert(Turbolinks)

  describe '#visit', ->
    it 'subsequent visits abort previous XHRs', (done) ->
      pageReceive = stub()
      $(document).on('page:receive', pageReceive)
      visit url: 'noScriptsOrLinkInHead', -> true
      visit url: 'noScriptsOrLinkInHead', ->
        assert(pageReceive.calledOnce, 'page:receive should only be emitted once!')
        done()

    it 'returns if pageChangePrevented', (done) ->
      $(document).one 'page:before-change', (event) ->
        event.preventDefault()
        assert.equal('/noScriptsOrLinkInHead', event.originalEvent.data)
        assert.equal(0, sandbox.server.requests.length)
        done()

      visit(url: 'noScriptsOrLinkInHead', options: { partialReplace: true, onlyKeys: ['turbo-area'] })

    it 'supports passing request headers', (done) ->
      visit url: 'noScriptsOrLinkInHead', options: { headers: {'foo': 'bar', 'fizz': 'buzz'} }, ->
        assert.equal('bar', sandbox.server.requests[0].requestHeaders['foo'])
        assert.equal('buzz', sandbox.server.requests[0].requestHeaders['fizz'])
        done()

    it 'calls a user-supplied callback', (done) ->
      yourCallback = stub()
      visit url: 'noScriptsOrLinkInHead', options: {callback: yourCallback}, ->
        assert(yourCallback.calledOnce, 'Callback was not called.')
        done()

  describe 'head link tag tracking', ->
    it 'dispatches page:after-link-inserted event when inserting a link on navigation', (done) ->
      linkTagInserted = sinon.spy()
      $(document).on 'page:after-link-inserted', linkTagInserted

      visit url: 'noScriptsOrLinkInHead', ->
        assertLinks([])
        visit url: 'singleLinkInHead', ->
          assertLinks(['foo.css'])
          assert.equal(linkTagInserted.callCount, 1)
          done()

    it 'dispatches page:after-link-removed event when removing a link on navigation', (done) ->
      linkTagRemoved = sinon.spy()
      $(document).on 'page:after-link-removed', linkTagRemoved

      visit url: 'singleLinkInHead', ->
        visit url: 'noScriptsOrLinkInHead', ->
          assert.equal(linkTagRemoved.callCount, 1)
          done()

    it 'inserts link with a new href into empty head on navigation', (done) ->
      visit url: 'noScriptsOrLinkInHead', ->
        assertLinks([])
        visit url: 'singleLinkInHead', ->
          assertLinks(['foo.css'])
          done()

    it 'inserts link with a new href into existing head on navigation', (done) ->
      visit url: 'singleLinkInHead', ->
        assertLinks(['foo.css'])
        visit url: 'twoLinksInHead', ->
          assertLinks(['foo.css', 'bar.css'])
          done()

    it 'inserts link with a new href before exiting scripts in head on navigation', (done) ->
      visit url: 'singleLinkInHead', ->
        assertLinks(['foo.css'])
        visit url: 'twoLinksInHeadReverseOrder', ->
          assertLinks(['bar.css', 'foo.css'])
          done()

    it 'does not reinsert link with existing href into identical head on navigation', (done) ->
      visit url: 'singleLinkInHead', ->
        assertLinks(['foo.css'])
        visit url: 'singleLinkInHead', ->
          assertLinks(['foo.css'])
          done()

    it 'removes link when navigating to a page with an empty head', (done) ->
      visit url: 'singleLinkInHead', ->
        assertLinks(['foo.css'])
        visit url: 'noScriptsOrLinkInHead', ->
          assertLinks([])
          done()

    it 'removes link when navigating to a page with the href missing', (done) ->
      visit url: 'twoLinksInHead', ->
        assertLinks(['foo.css', 'bar.css'])
        visit url: 'singleLinkInHead', ->
          assertLinks(['foo.css'])
          done()

    it 'many subsequent navigations do not break head asset tracking', (done) ->
      requestsToDo = 10

      recursiveVisit = ->
        visit url: 'twoLinksInHead', ->
          visit url: 'singleLinkInHead', ->
            assertLinks(['foo.css'])
            requestsToDo -=1
            return recursiveVisit() if requestsToDo > 0
            done()

      recursiveVisit()

      it 'many subsequent synchronous navigations do not break head asset tracking', (done) ->
        requestsToDo = 10

        recursiveVisit = ->
          visit url: 'twoLinksInHead'
          visit url: 'singleLinkInHead'
          visit url: 'twoLinksInHead', ->
              assertLinks(['foo.css', 'bar.css'])
              requestsToDo -=1
              return recursiveVisit() if requestsToDo > 0
              done()

        recursiveVisit()

    describe 'transforms the current head to have the same links in the same order as the upstream document with minimal moves', ->
      it 'maintains order when moving from an empty head to a page with link nodes.', (done) ->
        linkTagInserted = sinon.spy()
        $(document).on 'page:after-link-inserted', linkTagInserted
        visit url: 'fourLinksInHeadABCD', ->
          assertLinks(['a.css', 'b.css', 'c.css', 'd.css'])
          assert.equal(linkTagInserted.callCount, 4)
          done()

      it 'performs the minimal number of moves for an upwards transform ABCD to BCDA.', (done) ->
        visit url: 'fourLinksInHeadABCD', ->
          linkTagInserted = sinon.spy()
          $(document).on 'page:after-link-inserted', linkTagInserted
          visit url: 'fourLinksInHeadBCDA', ->
            assertLinks(['b.css', 'c.css', 'd.css', 'a.css'])
            assert.equal(linkTagInserted.callCount, 1) # Move A
            done()

      it 'performs the minimal number of moves for a downwards transform BCDA to ABCD.', (done) ->
        visit url: 'fourLinksInHeadBCDA', ->
          linkTagInserted = sinon.spy()
          $(document).on 'page:after-link-inserted', linkTagInserted
          visit url: 'fourLinksInHeadABCD', ->
            assertLinks(['a.css', 'b.css', 'c.css', 'd.css'])
            assert.equal(linkTagInserted.callCount, 1) # Move A
            done()

      it 'maintains order when moving from a head with links ABCD to links CDAB.', (done) ->
        visit url: 'fourLinksInHeadABCD', ->
          linkTagInserted = sinon.spy()
          $(document).on 'page:after-link-inserted', linkTagInserted
          visit url: 'fourLinksInHeadCDAB', ->
            assertLinks(['c.css', 'd.css', 'a.css', 'b.css'])
            assert.equal(linkTagInserted.callCount, 2) # Move A,B or C,D
            done()

      it 'maintains order when moving from a head with links ABCD to links CDBA.', (done) ->
        visit url: 'fourLinksInHeadABCD', ->
          linkTagInserted = sinon.spy()
          $(document).on 'page:after-link-inserted', linkTagInserted
          visit url: 'fourLinksInHeadCDBA', ->
            assertLinks(['c.css', 'd.css', 'b.css', 'a.css'])
            assert.equal(linkTagInserted.callCount, 2) # Move A,B
            done()

      it 'maintains order when moving from a head with links ABCD to links CBDA.', (done) ->
        visit url: 'fourLinksInHeadABCD', ->
          linkTagInserted = sinon.spy()
          $(document).on 'page:after-link-inserted', linkTagInserted
          visit url: 'fourLinksInHeadCBDA', ->
            assertLinks(['c.css', 'b.css', 'd.css', 'a.css'])
            assert.equal(linkTagInserted.callCount, 2) # Move A,B or A,C
            done()

      it 'maintains order when moving from a head with links ABCD to links DCBA.', (done) ->
        visit url: 'fourLinksInHeadABCD', ->
          linkTagInserted = sinon.spy()
          $(document).on 'page:after-link-inserted', linkTagInserted
          visit url: 'fourLinksInHeadDCBA', ->
            assertLinks(['d.css', 'c.css', 'b.css', 'a.css'])
            assert.equal(linkTagInserted.callCount, 3) # Move any 3
            done()

  describe 'head script tag tracking', ->
    it 'dispatches page:after-script-inserted event when inserting a script on navigation', (done) ->
      scriptTagInserted = sinon.spy()
      $(document).on 'page:after-script-inserted', scriptTagInserted

      visit url: 'noScriptsOrLinkInHead', ->
        visit url: 'singleScriptInHead', ->
          assert.equal(scriptTagInserted.callCount, 1)
          done()

    it 'inserts script with a new src into empty head on navigation', (done) ->
      visit url: 'noScriptsOrLinkInHead', ->
        assertScripts([])
        visit url: 'singleScriptInHead', ->
          assertScripts(['foo.js'])
          done()

    it 'inserts script with a new src into existing head on navigation', (done) ->
      visit url: 'singleScriptInHead', ->
        assertScripts(['foo.js'])
        visit url: 'twoScriptsInHead', ->
          assertScripts(['foo.js', 'bar.js'])
          done()

    it 'does not insert duplicate script tag on navigation into identical upstream head', (done) ->
      visit url: 'singleScriptInHead', ->
        assertScripts(['foo.js'])
        visit url: 'singleScriptInHead', ->
          assertScripts(['foo.js'])
          done()

    it 'does not insert duplicate script tag on navigation into superset upstream head', (done) ->
      visit url: 'singleScriptInHead', ->
        assertScripts(['foo.js'])
        visit url: 'twoScriptsInHead', ->
          assertScripts(['foo.js', 'bar.js'])
          done()

    it 'does not remove script when navigating to a page with an empty head', (done) ->
      visit url: 'singleScriptInHead', ->
        assertScripts(['foo.js'])
        visit url: 'noScriptsOrLinkInHead', ->
          assertScripts(['foo.js'])
          done()

    describe 'executes scripts in the order they are present in the dom of the upstream document', ->
      beforeEach -> window.actualExecutionOrder = []
      afterEach -> delete window.actualExecutionOrder

      it 'works in order ABC', (done) ->
        expectedScriptOrder = ['a', 'b', 'c']
        visit url: 'threeScriptsInHeadABC', ->
          assert.deepEqual(actualExecutionOrder, expectedScriptOrder)
          done()

      it 'works in order ACB', (done) ->
        visit url: 'threeScriptsInHeadACB', ->
          expectedScriptOrder = ['a', 'c', 'b']
          assert.deepEqual(actualExecutionOrder, expectedScriptOrder)
          done()

      it 'works in order BAC', (done) ->
        visit url: 'threeScriptsInHeadBAC', ->
          expectedScriptOrder = ['b', 'a', 'c']
          assert.deepEqual(actualExecutionOrder, expectedScriptOrder)
          done()

      it 'works in order BCA', (done) ->
        visit url: 'threeScriptsInHeadBCA', ->
          expectedScriptOrder = ['b', 'c', 'a']
          assert.deepEqual(actualExecutionOrder, expectedScriptOrder)
          done()

      it 'works in order CAB', (done) ->
        visit url: 'threeScriptsInHeadCAB', ->
          expectedScriptOrder = ['c', 'a', 'b']
          assert.deepEqual(actualExecutionOrder, expectedScriptOrder)
          done()

      it 'works in order CBA', (done) ->
        visit url: 'threeScriptsInHeadCBA', ->
          expectedScriptOrder = ['c', 'b', 'a']
          assert.deepEqual(actualExecutionOrder, expectedScriptOrder)
          done()

      it 'executes new scripts in the relative order they are present in the dom of the upstream document', (done) ->
        visit url: 'secondLibraryOnly', ->
          assert.equal(actualExecutionOrder[0], 'b')
          visit url: 'threeScriptsInHeadABC', ->
            assert.equal(actualExecutionOrder[1], 'a')
            assert.equal(actualExecutionOrder[2], 'c')
            done()

    it 'does not remove script nodes when navigating to a page with less script tags', (done) ->
      visit url: 'twoScriptsInHead', ->
        assertScripts(['foo.js', 'bar.js'])
        visit url: 'singleScriptInHead', ->
          assertScripts(['foo.js', 'bar.js'])
          done()

    it 'refreshes page when a data-turbolinks-track-script-as src changes', (done) ->
      visit url: 'singleScriptInHead', ->
        visit url: 'singleScriptInHeadWithDifferentSourceButSameName', ->
          assert(Turbolinks.fullPageNavigate.called, 'Should perform a full page refresh.')
          done()

    it 'it refreshes inline when a new data-turbolinks-track-script-as is added', (done) ->
      visit url: 'singleScriptInHead', ->
        visit url: 'differentSingleScriptInHead', ->
          assert(Turbolinks.fullPageNavigate.notCalled, 'Should not perform a full page refresh.')
          done()

  describe 'with partial page replacement', ->
    beforeEach -> window.globalStub = stub()

    it 'script tags are evaluated when they are the subject of a partial replace', (done) ->
      visit url: 'inlineScriptInBody', options: {partialReplace: true, onlyKeys: ['turbo-area']}, ->
        assert(globalStub.calledOnce, 'Script tag was not evaluated :(')
        done()

    it 'calls a user-supplied callback', (done) ->
      yourCallback = stub()
      visit url: 'noScriptsOrLinkInHead', options: {partialReplace: true, onlyKeys: ['turbo-area'], callback: yourCallback}, ->
        assert(yourCallback.calledOnce, 'Callback was not called.')
        done()

    it 'script tags are not evaluated if they have [data-turbolinks-eval="false"]', (done) ->
      visit url: 'inlineScriptInBodyTurbolinksEvalFalse', options: {partialReplace: true, onlyKeys: ['turbo-area']}, ->
        assert.equal(0, globalStub.callCount)
        done()

    it 'pushes state onto history stack', (done) ->
      visit url: 'noScriptsOrLinkInHead',  options: {partialReplace: true, onlyKeys: ['turbo-area']}, ->
        assert(Turbolinks.pushState.called, 'pushState not called')
        assert(Turbolinks.pushState.calledWith({turbolinks: true, url: urlFor('/noScriptsOrLinkInHead')}, '', urlFor('/noScriptsOrLinkInHead')), 'Turbolinks.pushState not called with proper args')
        assert.equal(0, replaceStateStub.callCount)
        assert.equal(1, sandbox.server.requests.length)
        done()

    it 'doesn\'t add a new history entry if updatePushState is false', (done) ->
      visit url: 'noScriptsOrLinkInHead', options: {partialReplace: true, onlyKeys: ['turbo-area'], updatePushState: false}, ->
        assert(pushStateStub.notCalled, 'pushState should not be called')
        assert(replaceStateStub.notCalled, 'replaceState should not be called')
        done()

    it 'uses just the part of the response body we supply', (done) ->
      visit url: 'noScriptsOrLinkInHead',  options: {partialReplace: true, onlyKeys: ['turbo-area']}, ->
        assert.equal("Hi there!", document.title)
        assert.notInclude(document.body.textContent, 'YOLO')
        assert.include(document.body.textContent, 'Hi bob')
        done()

    it 'triggers the page:load event with a list of nodes that are new (freshly replaced)', (done) ->
      visit url: 'noScriptsOrLinkInHead', options: {partialReplace: true, onlyKeys: ['turbo-area']}, (event) ->
        ev = event.originalEvent
        assert.instanceOf(ev.data, Array)
        assert.lengthOf(ev.data, 1)
        node = ev.data[0]

        assert.equal('turbo-area', node.id)
        assert.equal('turbo-area', node.getAttribute('refresh'))
        done()

    it 'does not trigger the page:before-partial-replace event more than once', (done) ->
      handler = stub()
      $(document).on 'page:before-partial-replace', handler

      visit url: 'noScriptsOrLinkInHead', options: {partialReplace: true, onlyKeys: ['turbo-area']}, ->
        assert(handler.calledOnce)
        done()

    it 'refreshes only outermost nodes of dom subtrees with refresh keys', (done) ->
      visit url: 'responseWithRefreshAlways', ->
        $(document).on 'page:before-partial-replace', (ev) ->
          nodes = ev.originalEvent.data
          assert.equal(2, nodes.length)
          assert.equal('div2', nodes[0].id)
          assert.equal('div1', nodes[1].id)

        visit url: 'responseWithRefreshAlways', options: {onlyKeys: ['div1']}, (ev) ->
          nodes = ev.originalEvent.data
          assert.equal(1, nodes.length)
          assert.equal('div1', nodes[0].id)
          done()
