using WebDriver
include("../citation_graph.jl")

# -------------------------------------------------------------------------------
# step 1: load citation graph from old data 
citationGraph = loadCitationGraph(".", "ijcai")

# -------------------------------------------------------------------------------
# step 2: open a webdriver session for data crawling 
capabilities = Capabilities("firefox")
wd = RemoteWebDriver(capabilities)
session = Session(wd)

# -------------------------------------------------------------------------------
# step 3: iterates through the nodes to be analyzed and update their info 
k = 0
for id in citationGraph.toBeAnalyzed
    global session
    global citationGraph
    node = citationGraph.nodes[id]
    
    # (3.1) define several utility functions
    # function waitForPageLoaded:
    #   whenever click!() or navigate!() is called, this function must be called to ensure the 
    #   webpage is fully loaded 
    function waitForPageLoaded()
        sleep(1)
        pageState = try
            script!(session, "return document.readyState")
        catch
            ""
        end
        for i = 1:30
            if pageState != "complete"
                sleep(1)
            end
        end
    end
    # function switchRoute:
    #   switch the webpage between references and citations 
    function switchRoute(routeName::String)::Bool
        routesGroup = Element(session, "css selector", "div.routes-group")
        route = Element(routesGroup, "css selector", "ma-call-to-action.au-target.route.active")
        if routeName != element_text(route)
            routes = Elements(routesGroup, "css selector", "ma-call-to-action.au-target.route")
            for r in routes
                if routeName == element_text(r) && "au-target route disabled" != element_attr(r, "class")
                    click!(r)
                    waitForPageLoaded()
                    return true
                end
            end
        else
            return true
        end
        return false
    end
    # function nextPage:
    #   go to next page of the results 
    function nextPage()::Bool
        try
            pager = Element(session, "css selector", "div.ma-pager")
            if pager === nothing
                return false
            end
            nextPageElem = Element(pager, "css selector", "i.icon-up.right.au-target")
            if nextPageElem !== nothing
                click!(nextPageElem)
                waitForPageLoaded()
                return true
            end
        catch
        end
        return false
    end
    # function getResultCount:
    #   get the (real) number of results 
    function getResultCount()
        count = 0
        try 
            resultElement = Element(session, "css selector", "div.results")
            infoElement = Element(resultElement, "css selector", "div.info.secondary-text")
            infoText = element_text(infoElement)
            count = parse(Int, split(infoText, "of")[2])
        catch
        end
        count
    end
    # function selectNewestFirst:
    #   ask the webpage to sort the result by order "NEWEST FIRST"
    function selectNewestFirst()
        try 
            resultElement = Element(session, "css selector", "div.results")
            dropdownElement = Element(resultElement, "css selector", "div.au-target.ma-dropdown")
            click!(dropdownElement)
            optionElements = Elements(resultElement, "css selector", "div.option.au-target")
            for optionElem in optionElements
                if element_text(optionElem) == "NEWEST FIRST"
                    click!(optionElem)
                    break
                end
            end
            waitForPageLoaded()
        catch
        end
    end

    # (3.2) navigate to the paper of this node on academic.microsoft.com
    url = "https://academic.microsoft.com/paper/$id/reference"
    navigate!(session, url)

    # (3.3) wait until the webpage is fully loaded
    waitForPageLoaded()

    # (3.4) get the number of references and citations from the webpage
    numRefs = 0
    numCites = 0
    try
        statsElement = Element(session, "css selector", "div.stats")
        statDataElements = Elements(statsElement, "css selector", "div.count")
        numRefs = parse(Int64, element_text(statDataElements[1]))
        numCites = parse(Int64, element_text(statDataElements[2]))
    catch
    end
    

    # (3.5) get references from the webpage
    oldRefSet = Set(node.refs)
    if numRefs > 0 && switchRoute("REFERENCES")
        realNumRefs = getResultCount()
        for iRef = 1:10:realNumRefs
            try
                resultElement = Element(session, "css selector", "div.results")
                maCardElements = Elements(resultElement, "css selector", "ma-card.au-target")
                for maCard in maCardElements
                    titleElement = Element(maCard, "css selector", "a.title")
                    refID = parse(Int, split(element_attr(titleElement, "href"),"/")[end-1])
                    if refID ∈ oldRefSet
                        continue 
                    end
                    push!(node.refs, refID)
                    println("new ref $refID for $id")

                    if refID ∉ keys(citationGraph.nodes)
                        refTitle = element_text(titleElement)
                        yearElements = Elements(maCard, "css selector", "span.year")
                        refYear = ""
                        for elem in yearElements
                            if element_text(elem) != ""
                                refYear = element_text(elem)
                            end
                        end
                        citationGraph.nodes[refID] = CitationNode(refID, refYear, refTitle, String[], Int[], Int[])
                    end
                end
            catch
                nothing
            end
            if !nextPage()
                break
            end
        end
    end

    # (3.6) get citations from the webpage
    oldCiteSet = Set(node.cites)
    if numCites > 0 && switchRoute("CITED BY")
        selectNewestFirst()
        realNumCites = getResultCount()
        for iCite = 1:10:realNumCites
            try
                resultElement = Element(session, "css selector", "div.results")
                maCardElements = Elements(resultElement, "css selector", "ma-card.au-target")
                for maCard in maCardElements
                    titleElement = Element(maCard, "css selector", "a.title")
                    citeID = split(element_attr(titleElement, "href"),"/")[end-1]
                    if citeID ∈ oldCiteSet
                        continue 
                    end
                    push!(node.cites, citeID)
                    println("new cite $citeID for $id")

                    if citeID ∉ keys(citationGraph.nodes)
                        citeTitle = element_text(titleElement)
                        yearElements = Elements(maCard, "css selector", "span.year")
                        citeYear = ""
                        for elem in yearElements
                            if element_text(elem) != ""
                                citeYear = element_text(elem)
                            end
                        end
                        citationGraph.nodes[citeID] = CitationNode(citeID, citeYear, citeTitle, String[], Int[], Int[])
                    end
                end
            catch
                nothing
            end
            if !nextPage()
                break
            end
        end
    end

    # (3.6) save result for every 100 paper 
    global k += 1
    println("paper $k processed")
    if k % 100 == 0
        saveCitationGraph(".", "ijcai", citationGraph)
        window_close!(session)
        session = Session(wd)
    end
end

# -------------------------------------------------------------------------------
# step 4: save result 
saveCitationGraph(".", "ijcai", citationGraph)