# ===========================================================================================
# struct CitationNode 
# brief description: The node structure of a citation graph, the data of which are collected
#                    from crawling the website https://academic.microsoft.com , which is the
#                    public service website of MAG(Microsoft Academic Graph) 
# fields:
#   id: The MAG(Microsoft Academic Graph) id of the paper at this node.
#       We can access the detail of the paper with the id by navigating the web link:
#       https://academic.microsoft.com/paper/$id 
#   year: The year of publication of this paper.
#   title: The title of the paper.
#   labels: The labels from MAG(Microsoft Academic Graph). 
#   refs: The references of this paper collected from MAG. 
#         Please note that this field could be inaccurate: MAG suffers delay of info.
#         Many new papers with refs don't have refs listed in MAG.
#   cites: The citations to this paper from other papers (also collected from MAG).
#         Please note that this field is as inaccurate as refs due to the same reason.
struct CitationNode
    id::Int
    year::Int
    title::String
    labels::Vector{String}
    refs::Vector{Int}
    cites::Vector{Int}
end

# ===========================================================================================
# struct CitationGraph 
# brief description: A data structure of citation graph, the data of which are collected from
#                    the website https://academic.microsoft.com , which is the public service
#                    website of MAG(Microsoft Academic Graph)
# fields:
#   nodes: The node of struct CitationNode stored in a dictionary with key = id  
#   toBeAnalyzed: The list of nodes to be analyzed. In ijcai_clustering dataset, these nodes 
#                 are those published in IJCAI. 
struct CitationGraph
    nodes::Dict{Int, CitationNode}
    toBeAnalyzed::Vector{Int}
end

# ===========================================================================================
# function tidyTitle
# brief description: Make a title more tidy before using it. The procedure include the 
#                    steps:
#                    (1) remove the spaces at the head and the tail of the title, 
#                    (2) replace "&lt;" with "<",
#                    (3) replace "&gt;" with ">", 
#                    (4) replace "&amp;" with "&",
#                    (5) replace "&quot;" with "\"",
#                    (6) replace "&apos;" with "'",
#                    (7) replace "&#[number];" with a corresponding unicode 
# input:
#   title: The String (text) of a title. 
# output:
#   A string of the tidied-up title.
function tidyTitle(title::String)::String
    # ---------------------------------------------------------------------------------------
    # step 1: remove the spaces at the head and the tail
    result = title
    while startswith(result, " ") || startswith(result, "\t")
        result = result[2:end]
    end
    while endswith(result, " ") || endswith(result, "\t")
        result = result[1:end-1]
    end

    # ---------------------------------------------------------------------------------------
    # step 2: replace "&lt;" with "<"
    result = replace(result, "&lt;"=>"<")

    # ---------------------------------------------------------------------------------------
    # step 3: replace "&gt;" with ">",
    result = replace(result, "&gt;"=>">")

    # ---------------------------------------------------------------------------------------
    # step 4: replace "&amp;" with "&"
    result = replace(result, "&amp;"=>"&")

    # ---------------------------------------------------------------------------------------
    # step 5: replace "&quot;" with "\""
    result = replace(result, "&quot;"=>"\"")

    # ---------------------------------------------------------------------------------------
    # step 6: "&apos;" with "'"
    result = replace(result, "&apos;"=>"'")

    # ---------------------------------------------------------------------------------------
    # step 7: replace "&#[number];" with a corresponding unicode
    positions = findall(r"&#([XxA-Fa-f]|\d)+;",result)
    toReplace = Pair{String,String}[]
    for pos in positions 
        s = result[pos[1]+2:pos[end]-1]
        if s[1] == 'X' || s[1] == 'x'
            push!(toReplace, "&#$s;"=>""*Char(parse(Int, "0$s")))
        else
            push!(toReplace, "&#$s;"=>""*Char(parse(Int, s)))
        end
    end
    for pattern in toReplace
        result = replace(result, pattern)
    end

    # ---------------------------------------------------------------------------------------
    # step 8: return the result 
    result
end 

# ===========================================================================================
# function loadCitationGraph
# brief description: Load data from three files (nodes, edges, labels) of a citation graph.
# input:
#   path: The name of the path where the three files are stored.
#   prefix: The prefix of the names of the three files. For example, the prefix of 
#           ijcai-citation-graph-nodes.csv is ijcai.
# output:
#    The citation graph represented by the three files. 
function loadCitationGraph(path::String, prefix::String)::CitationGraph
    # ---------------------------------------------------------------------------------------
    # step 1: prepare the data structure of the result
    result = CitationGraph(Dict{Int,CitationNode}(),Int[])

    # ---------------------------------------------------------------------------------------
    # step 2: assemble the file names for nodes, edges, and labels
    fileNameOfNodes = "$path/$prefix-citation-graph-nodes.csv"
    fileNameOfEdges = "$path/$prefix-citation-graph-edges.csv"
    fileNameOfLabels = "$path/$prefix-citation-graph-labels.csv"

    # ---------------------------------------------------------------------------------------
    # step 3: load the nodes
    # (3.1) open the file of Nodes
    fileOfNodes = open(fileNameOfNodes)

    # (3.2) examine the first line to check whether the file format is correct
    firstLine = readline(fileOfNodes)
    columnNames = replace.(split(firstLine, ","), " "=>"")
    @assert columnNames[1] == "#id" && columnNames[2] == "in-$prefix" && 
        columnNames[3] == "year" && columnNames[4] == "title"

    # (3.3) read the rest of lines
    for line in readlines(fileOfNodes)
        columns = split(line, ",")
        id = parse(Int, columns[1])
        toBeAnalyzed = parse(Bool, columns[2])
        year = parse(Int, columns[3])
        title = replace(columns[4], "[comma]"=>",")
        result.nodes[id] = CitationNode(id,year,title,String[],Int[],Int[])
        if toBeAnalyzed
            push!(result.toBeAnalyzed, id)
        end
    end

    # (3.4) close the file of Nodes
    close(fileOfNodes)

    # ---------------------------------------------------------------------------------------
    # step 4: load the edges
    # (4.1) open the file of edges
    fileOfEdges = open(fileNameOfEdges)

    # (4.2) examine the first line to check whether the file format is correct
    firstLine = readline(fileOfEdges)
    columnNames = replace.(split(firstLine, ","), " "=>"")
    @assert columnNames[1] == "#id" && columnNames[2] == "ref-id"

    # (4.3) read the rest of lines
    for line in readlines(fileOfEdges)
        columns = split(line, ",")
        id = parse(Int, columns[1])
        refID = parse(Int, columns[2])
        push!(result.nodes[id].refs, refID)
        push!(result.nodes[refID].cites, id)
    end

    # (4.4) close the file of edges
    close(fileOfEdges)

    # ---------------------------------------------------------------------------------------
    # step 5: load the labels
    # (5.1) open the file of labels
    fileOfLabels = open(fileNameOfLabels)

    # (5.2) examine the first line to check whether the file format is correct
    firstLine = readline(fileOfLabels)
    columnNames = replace.(split(firstLine, ","), " "=>"")
    @assert columnNames[1] == "#id" && columnNames[2] == "label"

    # (5.3) read the rest of lines
    for line in readlines(fileOfLabels)
        columns = split(line, ",")
        id = parse(Int, columns[1])
        label = columns[2]
        push!(result.nodes[id].labels, label)
    end

    # (5.4) close the file of labels
    close(fileOfLabels)

    # ---------------------------------------------------------------------------------------
    # step 6: return the result
    result
end

# ===========================================================================================
# function saveCitationGraph
# brief description: Save data to three files (nodes, edges, labels) of a citation graph.
# input:
#   path: The name of the path where the three files are stored.
#   prefix: The prefix of the names of the three files. For example, the prefix of 
#           ijcai-citation-graph-nodes.csv is ijcai.
#   citationGraph: The citation graph represented by the three files.
# output:
#   nothing  
function saveCitationGraph(path::String, prefix::String, citationGraph::CitationGraph)
    # ---------------------------------------------------------------------------------------
    # step 1: assemble the file names for nodes, edges, and labels
    fileNameOfNodes = "$path/$prefix-citation-graph-nodes.csv"
    fileNameOfEdges = "$path/$prefix-citation-graph-edges.csv"
    fileNameOfLabels = "$path/$prefix-citation-graph-labels.csv"

    # ---------------------------------------------------------------------------------------
    # step 2: save the nodes
    # (2.1) open the file of Nodes for writing
    fileOfNodes = open(fileNameOfNodes, "w")

    # (2.2) print the first line with the file format info
    println(fileOfNodes, "#id, in-$prefix, year, title")

    # (2.3) save data into the rest of lines
    idSetForAnalysis = Set(citationGraph.toBeAnalyzed)
    for (id, node) in citationGraph.nodes
        toBeAnalyzed = id ∈ idSetForAnalysis
        year = node.year 
        title = tidyTitle(replace(node.title, ","=>"[comma]"))
        println(fileOfNodes, "$id, $toBeAnalyzed, $year, $title")
    end

    # (2.4) close the file of Nodes
    close(fileOfNodes)

    # ---------------------------------------------------------------------------------------
    # step 3: save the edges
    # (3.1) open the file of edges for writing
    fileOfEdges = open(fileNameOfEdges, "w")

    # (3.2) print the first line with the file format info
    println(fileOfEdges, "#id, ref-id")

    # (3.3) save data into the rest of lines
    edgeSet = Set{Tuple{Int,Int}}()
    for (id, node) in citationGraph.nodes
        for refID in node.refs 
            push!(edgeSet, (id, refID))
        end
        for citeID in node.cites
            push!(edgeSet, (citeID, id)) 
        end 
    end
    for (id, refID) in edgeSet
        println(fileOfEdges, "$id, $refID")
    end

    # (3.4) close the file of edges
    close(fileOfEdges)

    # ---------------------------------------------------------------------------------------
    # step 4: save the labels
    # (4.1) open the file of labels for writing
    fileOfLabels = open(fileNameOfLabels, "w")

    # (4.2) print the first line with the file format info
    println(fileOfLabels, "#id, label")

    # (4.3) save data to the rest of lines 
    for id in idSetForAnalysis
        node = citationGraph.nodes[id]
        for label in node.labels
            println(fileOfLabels, "$id, $label") 
        end
    end

    # (4.4) close the file of labels
    close(fileOfLabels)
end
