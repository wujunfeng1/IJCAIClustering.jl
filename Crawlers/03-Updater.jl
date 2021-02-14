using WebDriver
include("citation_graph.jl")

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
for id in citationGraph.toBeAnalyzed[k+1:end]
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
        for i = 1:6
            if pageState != "complete"
                sleep(1)
            end
        end
    end
    # function switchRoute:
    #   switch the webpage between references and citations 
    function switchRoute(routeName::String)::Bool
        routesGroup = try 
            Element(session, "css selector", "div.routes-group")
        catch
            nothing
        end
        if routesGroup === nothing
            return false
        end
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
                url = current_url(session)
                click!(nextPageElem)
                waitForPageLoaded()
                resultElement = try
                    Element(session, "css selector", "div.results")
                catch
                    nothing
                end
                while resultElement === nothing
                    navigate!(session, url)
                    waitForPageLoaded()
                    nextPageElem = Element(pager, "css selector", "i.icon-up.right.au-target")
                    click!(nextPageElem)
                    waitForPageLoaded()
                    resultElement = try
                        Element(session, "css selector", "div.results")
                    catch
                        nothing
                    end
                end
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
            count = parse(Int, replace(split(infoText, "of")[2],","=>""))
        catch
        end
        count
    end
    # function selectNewestFirst:
    #   ask the webpage to sort the result by order "NEWEST FIRST"
    function selectNewestFirst()
        try
            url = current_url(session) 
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
            try
                Element(session, "css selector", "div.results")
            catch
                navigate!(session, url)
                waitForPageLoaded()
                selectNewestFirst()
            end
        catch
        end
    end
    # function setYearRange()
    #   When the citations are too many to list (i.e., > 500), we have to use year range filter 
    #   to narrow down the range (it is very rare a paper has more than 500 citations in a year).
    #   Therefore, we have to use the following function to set filters on the range of years.
    # input:
    #   yearIdx: the index of year range filter, 1 for the oldest valid year of the citations 
    # output:
    #   next yearIdx, or 0 if there is no next 
    function setYearRange(yearIdx::Int)::Int
        try
            clearAllElem = try
                Element(session, "css selector", "ma-call-to-action.clear-all.au-target")
            catch
                nothing
            end
            if clearAllElem !== nothing 
                click!(clearAllElem)
                waitForPageLoaded()
            end
            dropdownElem = Element(session, "css selector", "div.au-target.ma-year-range-dropdown")
            click!(dropdownElem)
            dropdownElem2 = Element(session, "css selector", "div.au-target.ma-year-range-dropdown.expanded")
            yearElems = Elements(dropdownElem2, "css selector", "div.au-target.year-item")
            numYearElems = length(yearElems)
            click!(yearElems[yearIdx])
            yearElems = Elements(dropdownElem2, "css selector", "div.au-target.year-item")
            click!(yearElems[yearIdx])
            waitForPageLoaded()
            if yearIdx + 1 <= numYearElems
                yearIdx + 1
            else
                0
            end
        catch
            0
        end 
    end
    # function fetchCites
    function fetchCites(oldCiteSet::Set{Int}, realNumCites::Int)
        if realNumCites == 0
            return
        end
        if realNumCites <= 500
            selectNewestFirst()
        end
        for iCite = 1:10:realNumCites
            resultElement = try
                Element(session, "css selector", "div.results")
            catch
                nothing
            end
            if resultElement === nothing
                break
            end
            maCardElements = Elements(resultElement, "css selector", "ma-card.au-target")
            for maCard in maCardElements
                titleElement = Element(maCard, "css selector", "a.title")
                citeID = parse(Int, split(element_attr(titleElement, "href"),"/")[end-1])
                if citeID ∈ oldCiteSet
                    continue 
                end
                push!(node.cites, citeID)
                println("new cite $citeID for $id")

                if citeID ∉ keys(citationGraph.nodes)
                    citeTitle = element_text(titleElement)
                    yearElements = Elements(maCard, "css selector", "span.year")
                    citeYear = 0
                    for elem in yearElements
                        if element_text(elem) != ""
                            citeYear = parse(Int, element_text(elem))
                        end
                    end
                    citationGraph.nodes[citeID] = CitationNode(citeID, citeYear, citeTitle, String[], Int[], Int[])
                end
            end
            if !nextPage()
                break
            end
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
        numRefs = parse(Int64, replace(element_text(statDataElements[1]),","=>""))
        numCites = parse(Int64, replace(element_text(statDataElements[2]),","=>""))
    catch
    end   

    # (3.5) get references from the webpage
    oldRefSet = Set(node.refs)
    if numRefs > 0 && switchRoute("REFERENCES")
        realNumRefs = getResultCount()
        for iRef = 1:10:realNumRefs
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
                    refYear = 0
                    for elem in yearElements
                        if element_text(elem) != ""
                            refYear = parse(Int, element_text(elem))
                        end
                    end
                    citationGraph.nodes[refID] = CitationNode(refID, refYear, refTitle, String[], Int[], Int[])
                end
            end
            if !nextPage()
                break
            end
        end
    end

    # (3.6) get citations from the webpage
    oldCiteSet = Set(node.cites)
    if numCites > 0 && switchRoute("CITED BY")
        realNumCites = getResultCount()
        if realNumCites > 500
            yearIdx = 1
            while yearIdx > 0
                yearIdx = setYearRange(yearIdx)
                realNumCites = getResultCount()
                fetchCites(oldCiteSet, realNumCites)
            end
        else
            fetchCites(oldCiteSet, realNumCites)
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