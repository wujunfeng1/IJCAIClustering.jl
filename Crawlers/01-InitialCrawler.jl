using HTTP
using Gumbo
using Cascadia

# step 1: get the web page of IJCAI at ma-graph.org
# the MAG ID of IJCAI is 1203999783
conferenceID = 1203999783
url = "http://ma-graph.org:8080/mag-pubby/page/$conferenceID"
res = HTTP.get(url)

# step 2: extract html from the webpage and parse it
body = String(res)
html = parsehtml(body)

# step 3: extract all a.uri and find matches
qres = eachmatch(sel"a.uri", html.root)
for elem in qres
    elemText = text(elem)
    if startswith(elemText, "http://ma-graph.org:8080/mag-pubby/entity/")
        # download the elem's html
        idChild = split(elemText,"/")[end]
        resURL = "http://ma-graph.org:8080/mag-pubby/page/$idChild"
        println(resURL)
        resChild = try
            HTTP.get(resURL)
        catch
            nothing
        end
        if resChild === nothing
            continue
        end
        bodyChild = String(resChild)
        open("CrawlerSpace/$idChild.txt", "w") do fileChild
            println(fileChild, bodyChild)
        end
    end
end
