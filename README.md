# Deploy a Docker Container to a Digital Ocean Droplet

I’ve been working with Docker as a developer for over a year now and though it
was a steep learning curve at the beginning I’m finding definite reasons to
continue using it to do local development. One thing that I didn’t have much
experience with, however, was the other side of the coin: deployments of
containerized application to real servers.

This article arose from my curiosity on how to do small-scale deployments of
dockerized applications. For companies managing wide deployments over a large
infrastructure there are definitely a healthy number of tools to choose from,
but if I have a single web service with a database, for instance, how would I
go about automating those deployments?

For the purposes of this tutorial we’re going to…

* Create a single HTML page and serve it from nginx.
* Configure this container to serve the web page
* Push it to a Docker hub repository which we will also create
* Create droplet, a small server, in the parlance of Digital Ocean
* Configure Capistrano to manage deployments of containers to the droplet
* Get a full change/build/deploy sequence going

From there I hope you can pivot in whatever direction you require to build on
this simple tutorial.

#### A Note on Software Versions
Docker specifically and web tooling in general moves notoriously quickly, so
we’re going to list the exact versions of the software we use in this tutorial:

| Software | Version |
|----------|:---------:|
|docker|1.12.0|
|nginx|1.11.1|
|ruby|2.3.0|
|capistrano|3.5.0|
|Digital Ocean droplet|Ubuntu Docker 1.11.1 on 14.04|

## Create DigitalOcean Droplet
The first step is to create a server where we can deploy our containers. To
simplify the setup and configuration of the host we used a preconfigured
‘Docker 1.11.1 on Ubuntu 14.04’ droplet from Digital Ocean using this tutorial.
For the purposes of what we’re doing the cheapest option (512MB RAM at $5/mo)
is fine. You can destroy this droplet once you’re done with the tutorial.

For later, ensure you add a public key to the droplet so that your machine can
deploy without passwords via Capistrano.

## Create our Web Page
Create a directory on your development machine to hold the code for the static
web site we’ll be deploying. Then create an empty Dockerfile and index.html
page for our static site.

```bash
~ $ mkdir -p dockertest/src
~ $ cd dockertest
~/dockertest $ touch ./Dockerfile src/index.html
```

Open site/index.html in your favorite editor, put some simple page content in there and save the file:

```html
<!doctype html>
<html>
    <head>
        <title>Dockertest</title>
    </head>
    <body>
      <p>Hello there, welcome to docker.</p>
    </body>
</html>
```

## Dockerize the Site
We now have a static web site we can serve from nginx through Docker. Our next
step is to create the Dockerfile that we’ll use to build the container image.

The Dockerfile for this site is going to be very simple- we’re going to base it
off of the nginx base image, and then copy the HTML file into the document root
of the container.

```Dockerfile
FROM nginx

COPY ./src/index.html /usr/share/nginx/html
```

## Build & Test Locally
Now we have everything we need to build and test our Docker container locally.

First we build from the Dockerfile and tag it with a name

```bash
~/dockertest $ docker build -t dockertest
```

Next we’ll run the container

```bash
~/dockertest $ docker run --name my-instance -p 3000:80 -d dockertest
```

We should now be able to pop open a browser on your development machine and
test! Navigate to http://localhost:3000 and you should see the static site we
created above.

Now let’s bring the container down because we’ll be changing up the names a
little bit as we move towards deploying it to our droplet.

```bash
~/dockertest $ docker stop my-instance
dockertest
~/dockertest $ docker rm -f my-instance
dockertest
```

## Create Docker Hub Repository
Our next step is to create a repository on Docker Hub where we can push our
container builds. Go to http://hub.docker.com and create an account if you
don’t already have one.

Create a new public repository and name it dockertest. It should now be called
*<yourusername>/dockertest* and be ready for images to be pushed.

## Tag & Push Build to Docker Hub Repository
Now we’re going to build another image but tag it so it may be pushed to Docker
Hub. Notice that the tag matches the name of the repository. We’re going to tag
this first version as `1.0.0` and then we’re going to add a second tag of
`latest`.

```bash
~/dockertest $ docker build -t <yourusername>/dockertest:1.0.0
~/dockertest $ docker tag <yourusername>/dockertest:1.0.0 <yourusername>/dockertest:latest
```

Finally, we’ll push all of our tags up to Docker Hub

```bash
~/dockertest $ docker push <yourusername>/dockertest
```

It should push all the tags we’ve created. You can double-check that everything
worked by refreshing the Docker Hub repository page in your browser and
ensuring the tags are listed  there now.

## Install Capistrano
Ok, we’ve dockerized, built, and pushed our static site to Docker Hub and now
we’re going to build out the capistrano deployment so we can do initiate
deploys from our development machine.

We’re going to use Capistrano to orchestrate the commands on the remote host.
You could totally do this step with bash scripts, but if we were to start
talking to two different servers (maybe one for our database container and one
for our application container) then cap may scale better. There’s also
obviously a point where capistrano is no longer sufficient and you’ll have to
move into the world of scheduling and orchestration.

First create a file called `Gemfile` in your project root. Open it up and put the
following in it:

```ruby
source 'https://rubygems.org'

gem 'capistrano'
```

Now install the capistrano gem (and bundler if need be).

```bash
~/dockertest $ gem install bundler
~/dockertest $ bundle install
```

Next we’ll generate the config files for capistrano

```bash
~/dockertest $ bundle exec cap install
```

You should now see a Capfile in the project root and a config folder with some
stage-specific files in it (production.rb, staging.rb, etc.) You’ll also have a
lib folder with some capistrano support files.

```bash
~/dockertest $ tree .
├── Capfile
├── Dockerfile
├── Gemfile
├── Gemfile.lock
├── config
│   ├── deploy
│   │   ├── production.rb
│   │   └── staging.rb
│   └── deploy.rb
├── lib
│   └── capistrano
│       └── tasks
├── log
│   └── capistrano.log
└── src
    └── index.html
```

## Build Capistrano Docker Task
Open up config/deploy.rb and we’ll add a custom task for pulling the latest
image from Docker Hub and restarting the container on the host. You can add
this block of code to the bottom of the file.

```ruby
namespace :deploy do
  task :docker do
    on roles(:docker) do |host|
      account = "<youraccountname>"
      image_name = "dockertest"

      puts "============= Starting Docker Update ============="
      execute "docker stop #{image_name}; echo 0"
      execute "docker rm -f #{image_name}; echo 0"
      execute "docker pull #{account}/#{image_name}:latest"
      execute "docker run -p 80:80 -d --name #{image_name} #{account}/#{image_name}:latest"
    end
  end
end
```

This task stops any running containers and removes them, then pulls down the
latest from the Docker Hub repository and then starts it running.

Now open `config/deploy/production.rb` and add your server definition:

```ruby
server 'your.droplet.ipaddress.here', user: 'root', roles: %w{docker}
```

## Deploy with Capistrano
Everything is in place! From your project root run…

```bash
~/dockertest $ bundle exec cap production deploy:docker
```

You should see a lot of updates fly by as capistrano SSH’s to your droplet and
runs the commands to pull down the latest static site image from your Docker
Hub repo and then start it running.

You should be able to open your browser to http://your.droplet.ipaddress.here/
and see your static site content!

## Make a Change and Re-deploy
Now we’re ready to ensure we can pipeline our changes out to the server. Open
`src/index.html` again, change some of the content and save the file. Once it’s
saved then run the following:

```bash
~/dockertest $ docker build -t <yourusername>/dockertest:1.0.1
~/dockertest $ docker tag <yourusername>/dockertest:1.0.1 <yourusername>/dockertest:latest
~/dockertest $ docker push <yourusername>/dockertest
~/dockertest $ bundle exec cap production deploy:docker
```

Once the last command has finished, refresh your browser and you should see
your changes deployed to the server!

From here you can go in several different directions:

* Customize the Dockerfile to meet your configuration needs
* Customize the Capistrano task to better address your deployment needs
* Automate the building and pushing of images (during a continuous integration
    build, for example)
* Automate the deployment at the end of a successful continuous integration
    build

These are all of the base tools you should need to build a docker deployment
pipeline using capistrano.

---

this is an [adorable](http://adorable.io) creation






