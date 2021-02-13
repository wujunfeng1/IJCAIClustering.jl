using HTTP
using Gumbo
using Cascadia
include("../citation_graph.jl")

# -------------------------------------------------------------------------------
# step 1: load citation graph from old data 
citationGraph = loadCitationGraph(".", "ijcai")

# -------------------------------------------------------------------------------
# step 2: create an ID set to judge whether an ID is of a paper to be analyzed  
idSetForAnalysis = Set{Int}(citationGraph.toBeAnalyzed)
oldIDSet = copy(idSetForAnalysis)

# -------------------------------------------------------------------------------
# step 3: update the ID set with new data  
for fileName in readdir("CrawlerSpace")
    id = parse(Int, split(fileName, ".")[1])
    push!(idSetForAnalysis, id)
end

# -------------------------------------------------------------------------------
# step 4: load new data and merge them with old data  
fosDict = Dict{Int,String}()
for fileName in readdir("CrawlerSpace")
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.1) load new data from file 
    html = parsehtml(read("CrawlerSpace/$fileName", String))
    id = parse(Int, split(fileName, ".")[1])
    
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.2) parse new data 
    title = ""
    year = 0
    numCites = 0
    numRefs = 0
    cites = Int[]
    refs = Int[]
    fos = Int[]
    for rowElem in eachmatch(sel"tr", html.root)
        rowNameElem = eachmatch(sel"td.property", rowElem)
        if length(rowNameElem) == 0
            continue
        end
        rowName = text(rowNameElem[1])
        if rowName == "?: citationCount"
            numCites = parse(Int, split(text(eachmatch(sel"span.literal",
                rowElem)[1]),"\n")[1])
        elseif rowName == "is ?: cites of"
            for elem in eachmatch(sel"a.uri",rowElem)
                elemText = text(elem)
                if startswith(elemText, "http://ma-graph.org:8080/mag-pubby/entity/")
                    citeID = parse(Int, split(elemText,"/")[end])
                    push!(cites, citeID)
                end
            end
        elseif rowName == "?: cites"
            for elem in eachmatch(sel"a.uri",rowElem)
                elemText = text(elem)
                if startswith(elemText, "http://ma-graph.org:8080/mag-pubby/entity/")
                    refID = parse(Int, split(elemText,"/")[end])
                    push!(refs, refID)
                end
            end
        elseif rowName == "?: hasDiscipline"
            for elem in eachmatch(sel"a.uri",rowElem)
                elemText = text(elem)
                if startswith(elemText, "http://ma-graph.org:8080/mag-pubby/entity/")
                    fosID = parse(Int, split(elemText,"/")[end])
                    push!(fos, fosID)
                end
            end
        elseif rowName == "?: publicationDate"
            year = parse(Int, split(split(text(eachmatch(sel"span.literal",
                rowElem)[1]),"\n")[1],"-")[1])
        elseif rowName == "?: referenceCount"
            numRefs = parse(Int, split(text(
                eachmatch(sel"span.literal", rowElem)[1]),"\n")[1])
        elseif rowName == "?: title"
            title = replace(split(text(eachmatch(sel"span.literal",
                rowElem)[1]),"\n")[1], ","=>"[comma]")
        end
    end

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.3) create new node in citationGraph when necessary 
    if id ∉ keys(citationGraph.nodes)
        println("inserting $year, $title")
        citationGraph.nodes[id] = CitationNode(id,year,title,String[],Int[],Int[])
    end

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.4) make sure the node of this id is to be analyzed  
    if id ∉ oldIDSet
        push!(citationGraph.toBeAnalyzed, id)
    end

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.5) fetch the node from citationGraph 
    node = citationGraph.nodes[id]
    oldRefSet = Set(node.refs)
    oldCiteSet = Set(node.cites)
    oldLabelSet = Set(node.labels)

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.6) merge refs of this node  
    for refID in refs 
        if refID ∉ keys(citationGraph.nodes)
            println("fetching new ref $refID")
            resURL = "http://ma-graph.org/entity/$refID"
            res = try 
                HTTP.get(resURL)
            catch
                nothing 
            end
            if res === nothing
                continue 
            end 
            body = String(res)
            lines = split(body, "\n")
            title = ""
            year = 0
            for line in lines 
                if occursin(r"ns\d+:title", line) 
                    title = split(line,"\"")[2] 
                elseif occursin(r"ns\d+:publicationDate", line) 
                    year = parse(Int, split(split(line,"\"")[2],"-")[1]) 
                end 
            end
            citationGraph.nodes[refID] = CitationNode(refID,
                year,title,String[],Int[],Int[])
        end
        if refID ∉ oldRefSet
            push!(node.refs, refID)
        end
    end
    
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.7) merge cites of this node  
    for citeID in cites
        if citeID ∉ keys(citationGraph.nodes)
            println("fetching new cite $citeID")
            resURL = "http://ma-graph.org/entity/$citeID"
            res = try 
                HTTP.get(resURL)
            catch
                nothing 
            end
            if res === nothing
                continue 
            end 
            body = String(res)
            lines = split(body, "\n")
            title = ""
            year = 0
            for line in lines 
                if occursin(r"ns\d+:title", line) 
                    title = split(line,"\"")[2] 
                elseif occursin(r"ns\d+:publicationDate", line) 
                    year = parse(Int, split(split(line,"\"")[2],"-")[1]) 
                end  
            end
            citationGraph.nodes[citeID] = CitationNode(citeID,
                year,title,String[],Int[],Int[])
        end
        if citeID ∉ oldCiteSet
            push!(node.cites, citeID)
        end
    end

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # (4.8) merge fos of this node  
    for fosID in fos
        if fosID ∉ keys(fosDict)
            println("fetching new fos $fosID")
            resURL = "http://ma-graph.org/entity/$fosID"
            res = try 
                HTTP.get(resURL)
            catch
                nothing 
            end
            if res === nothing
                continue 
            end
            body = String(res)
            lines = split(body, "\n")
            fosName = "FOS $fosID"
            for line in lines 
                if occursin("foaf:name",line) 
                    fosName = split(line,"\"")[2]
                    break 
                end
            end
            fosDict[fosID] = fosName
        end
        fosName = fosDict[fosID]
        if fosName ∉ oldLabelSet
            push!(node.labels, fosName)
        end 
    end
end

saveCitationGraph(".", "ijcai", citationGraph)